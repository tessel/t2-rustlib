#!/bin/bash

# THIS IS A GIANT HACK
# if you think this would be a good idea if it weren't so terrible, go read https://github.com/rust-lang/rfcs/pull/1133

set -e

# Parse args
for i in "$@"
do
case $i in
    --rust-prefix=*)
    RUST_PREFIX=$(readlink -f "${i#*=}")
    shift
    ;;
    --rust-git=*)
    RUST_TREE=$(readlink -f "${i#*=}")
    shift
    ;;
    --target-json=*)
    JSON="${i#*=}"
    shift
    ;;
    *)
        # unknown option
    ;;
esac
done

# Sanity-check args
if [ ! -f $RUST_PREFIX/bin/rustc ]; then
    echo $RUST_PREFIX/bin/rustc does not exist. Pass --rust-prefix=/usr/local
    exit 1
fi

if [ ! -d $RUST_TREE/.git ]; then
    echo 'Pass --rust-git=path to rust git tree (git clone https://github.com/rust-lang/rust)'
    exit 1
fi

export PATH=$RUST_PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$RUST_PREFIX/lib
export RUSTLIB=$RUST_PREFIX/lib/rustlib
export RUSTC=$RUST_PREFIX/bin/rustc

RUST_VERSION=$($RUSTC --version | cut -f2 -d ' ')
RUST_GIT_VERSION=$($RUSTC --version | cut -f2 -d'(' | cut -f1 -d' ')

if ($RUSTC --version | grep -q nightly); then
    echo "Using a nightly rustc"
else
    echo "Unlocking stable rustc to support unstable features. You get to keep both pieces when this breaks."
    export RUSTC_BOOTSTRAP_KEY=$(echo -n $RUST_VERSION | md5sum | cut -c1-8)
    echo "Bootstrap key is '$RUSTC_BOOTSTRAP_KEY'"
fi

export HOST=x86-64-linux-gnu
export RUST_TARGET_PATH=$(dirname $(readlink -f "$JSON"))
export TARGET=$(basename $JSON .json)

# Parse the target JSON into environment variables
source <( cat "$JSON" | python -c '
import json, sys
j = json.load(sys.stdin)
print "export ARCH=%s"%(j["arch"])
print "export CC=%s"%(j["c-compiler"])
print "export AR=%s"%(j["ar"])
print "export CFLAGS=\"%s\""%(j["c-flags"])
print "export LINKFLAGS=\"%s\""%(j["c-link-flags"])
print "export TRIPLE=%s"%(j["c-triple"])
')

export FILENAME_EXTRA=$($RUSTC --version | cut -d' ' -f 2 | tr -d $'\n' | md5sum | cut -c 1-8)

export BUILD=$(mktemp -d --suffix=-rust-cross)
DEST="${RUSTLIB}/${TARGET}/lib"

cd $RUST_TREE
git checkout $RUST_GIT_VERSION || (git fetch; git checkout $RUST_GIT_VERSION)
git submodule update --init


# Build compiler-rt

mkdir "$BUILD/comprt"
make -C "$RUST_TREE/src/compiler-rt" \
    ProjSrcRoot="$RUST_TREE/src/compiler-rt" \
    ProjObjRoot="$(realpath $BUILD/comprt)" \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$AR s" \
    CFLAGS="$CFLAGS" \
    TargetTriple=$TRIPLE \
    multi_arch-m32
mv "$BUILD/comprt/multi_arch/m32/libcompiler_rt.a" "$BUILD/libcompiler-rt.a"

# Build libbacktrace

mkdir "$BUILD/libbacktrace"
(cd "$BUILD/libbacktrace" &&
    CC="$CC" \
    AR="$AR" \
    RANLIB="$AR s" \
    CFLAGS="$CFLAGS -fno-stack-protector" \
        "$RUST_TREE/src/libbacktrace/configure" \
            --build=$TRIPLE \
            --host=$HOST
    make INCDIR="$RUST_TREE/src/libbacktrace"
)

mv "$BUILD/libbacktrace/.libs/libbacktrace.a" "$BUILD"

# Build crates
# Use the rust build system to obtain the target crates in dependency order.
# TODO: use the makefile to build the C libs above

cat > "${BUILD}/hack.mk" <<'EOF'
RUSTC_OPTS = -Copt-level=2 --target=$(TARGET) \
      -L $(BUILD) --out-dir=$(BUILD) -C extra-filename=-$(FILENAME_EXTRA)

define BUILD_CRATE
$(1): $$(filter-out native:%,$$(DEPS_$(1)))
	$(RUSTC) $(CRATEFILE_$(1)) $(RUSTC_OPTS) $(RUSTFLAGS_$(1))

.PHONY: $(1)
endef

$(foreach crate,$(CRATES),$(eval $(call BUILD_CRATE,$(crate))))

EOF

make -f mk/util.mk -f mk/crates.mk -f "${BUILD}/hack.mk" std CFG_DISABLE_JEMALLOC=1

rm -rf "$DEST"
mkdir -p "$DEST"
mv "$BUILD"/*.rlib "$BUILD"/*.so "$BUILD"/*.a "$DEST"
rm -rf "$BUILD"

echo "Libraries are in ${DEST}."
