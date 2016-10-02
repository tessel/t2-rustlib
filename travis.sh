#!/bin/bash

set -e

# Upload tessel2.json
aws s3 cp tessel2.json s3://builds.tessel.io/t2/sdk/tessel2.json --acl public-read || true

if [ ! -d t2-sdk ]; then
  curl -LO https://s3.amazonaws.com/builds.tessel.io/t2/OpenWRT+SDK/OpenWrt-SDK-ramips-mt7620_gcc-4.8-linaro_uClibc-0.9.33.2.Linux-x86_64.tar.bz2
  tar xf OpenWrt-SDK-ramips-mt7620_gcc-4.8-linaro_uClibc-0.9.33.2.Linux-x86_64.tar.bz2
  mv OpenWrt-SDK-ramips-mt7620_gcc-4.8-linaro_uClibc-0.9.33.2.Linux-x86_64 t2-sdk
fi
export STAGING_DIR=$PWD/t2-sdk/staging_dir
export PATH=$STAGING_DIR/toolchain-mipsel_24kec+dsp_gcc-4.8-linaro_uClibc-0.9.33.2/bin/:$PATH

if [ ! -d rust ]; then
  git clone https://github.com/rust-lang/rust
fi

curl -LO https://static.rust-lang.org/dist/rust-$RUST_VERSION-x86_64-unknown-linux-gnu.tar.gz
tar xf rust-$RUST_VERSION-x86_64-unknown-linux-gnu.tar.gz
rust-$RUST_VERSION-x86_64-unknown-linux-gnu/install.sh --prefix=$PWD/rust-root

./rust-cross-libs.sh --rust-prefix=$PWD/rust-root --rust-git=rust --target-json=tessel2.json

tar -cvzf t2-rustlib-$RUST_VERSION.tar.gz -C /home/travis/build/tessel/t2-rustlib/rust-root/lib/rustlib/tessel2/lib .
aws s3 cp t2-rustlib-$RUST_VERSION.tar.gz s3://builds.tessel.io/t2/sdk/t2-rustlib-$RUST_VERSION.tar.gz --acl public-read
