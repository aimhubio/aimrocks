#!/bin/bash
curl -L https://www.zlib.net/fossils/zlib-1.2.11.tar.gz -o zlib-1.2.11.tar.gz
tar zxvf zlib-1.2.11.tar.gz
cd zlib-1.2.11/
ls -lhatr
./configure
make CFLAGS="-fPIC" CXXFLAGS="-fPIC"
make install prefix=..
cp libz.so.1.2.11 ../lib/libz.so
cd ..
rm -rf zlib-1.2.11/ zlib-1.2.11.tar.gz
