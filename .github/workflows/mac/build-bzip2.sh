#!/bin/bash
set -e

cd $AIM_DEP_DIR
curl https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz -o bzip2-1.0.8.tar.gz
tar zxvf bzip2-1.0.8.tar.gz
cd bzip2-1.0.8/
make CFLAGS="-fPIC" CXXFLAGS="-fPIC"
make install PREFIX=..
cd ../
rm -rf bzip2-1.0.8 bzip2-1.0.8.tar.gz
