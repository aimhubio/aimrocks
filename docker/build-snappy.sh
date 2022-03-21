#!/bin/bash
curl -L https://github.com/google/snappy/archive/1.1.8.tar.gz -o snappy-1.1.8.tar.gz
tar zxvf snappy-1.1.8.tar.gz
cd snappy-1.1.8
mkdir build
cd build
cmake CFLAGS="-fPIC" CXXFLAGS="fPIC" -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=ON ..
make
make PREFIX=.. install
cp libsnappy.so.1.1.8 ../../lib/libsnappy.so
cd ../..
rm -rf snappy-1.1.8 snappy-1.1.8.tar.gz
