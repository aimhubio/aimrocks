#!/bin/bash
curl -L https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz -o bzip2-1.0.8.tar.gz
tar zxvf bzip2-1.0.8.tar.gz
cd bzip2-1.0.8/
make CFLAGS="-fPIC" CXXFLAGS="-fPIC"
make -f Makefile-libbz2_so CFLAGS="-fPIC" CXXFLAGS="-fPIC"
make -n install PREFIX=..
cp libbz2.so.1.0 ../lib/libbz2.so
cd ..
rm -rf bzip2-1.0.8/ bzip2-1.0.8.tar.gz
