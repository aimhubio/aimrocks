#!/bin/bash

# Preparing local dependency directories
mkdir -p /opt/aimrocks_deps
cd /opt/aimrocks_deps/
export AIM_DEP_DIR=/opt/aimrocks_deps

mkdir -p lib
mkdir -p include

# Installing CMake
/opt/python/cp37-cp37m/bin/python -m pip install cmake
ln -s /opt/python/cp37-cp37m/bin/cmake /usr/bin/cmake
PATH=/opt/python/cp37-cp37m/bin:$PATH

# Building third party dependencies
/opts/aimrocks/docker/build-zlib.sh
/opts/aimrocks/docker/build-bzip2.sh
/opts/aimrocks/docker/build-zstd.sh
/opts/aimrocks/docker/build-lz4.sh
/opts/aimrocks/docker/build-snappy.sh
/opts/aimrocks/docker/build-rocksdb.sh
