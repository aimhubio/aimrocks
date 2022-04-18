#!/bin/bash
curl -L https://github.com/google/snappy/archive/1.1.8.tar.gz -o snappy-1.1.8.tar.gz
tar zxvf snappy-1.1.8.tar.gz
cd snappy-1.1.8
mkdir build
cd build
cmake -DCMAKE_INSTALL_PREFIX="../.." CFLAGS="-fPIC" CXXFLAGS="fPIC" -DCMAKE_POSITION_INDEPENDENT_CODE=ON ..
make
make install
cd ../..
rm -rf snappy-1.1.8 snappy-1.1.8.tar.gz
