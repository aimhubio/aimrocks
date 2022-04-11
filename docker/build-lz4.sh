#!/bin/bash
curl -L  https://github.com/lz4/lz4/archive/v1.9.3.tar.gz -o lz4-1.9.3.tar.gz
tar zxvf lz4-1.9.3.tar.gz
cd lz4-1.9.3
make CFLAGS="-fPIC" CXXFLAGS="-fPIC"
make PREFIX=.. install
cd ..
rm -rf lz4-1.9.3 lz4-1.9.3.tar.gz
