#!/bin/bash
set -e

cd $AIM_DEP_DIR
curl -L https://github.com/facebook/zstd/archive/v1.1.3.tar.gz -o zstd-1.1.3.tar.gz
tar zxvf zstd-1.1.3.tar.gz
cd zstd-1.1.3
make CFLAGS="-fPIC" CXXFLAGS="-fPIC"
make install PREFIX=$PWD/..
cd ..
rm -rf zstd-1.1.3 zstd-1.1.3.tar.gz
