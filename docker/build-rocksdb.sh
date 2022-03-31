#!/bin/bash
# check OS version
if [[ -f /etc/redhat-release ]]
then
  if [[ $(< /etc/redhat-release) == "CentOS release 5"* ]]
  then
    # CentOS 5
    export platform=centos_5
  fi
fi

rm -rf lib/lib*.so*

curl -L https://github.com/facebook/rocksdb/archive/6.29.fb.tar.gz -o rocksdb-6.29.fb.tar.gz
tar zxvf rocksdb-6.29.fb.tar.gz
cd rocksdb-6.29.fb
if [[ $platform == centos_5 ]]
then
  cp /opt/aimrocks_deps/rocksdb_sched.patch .
  patch port/port_posix.cc rocksdb_sched.patch
fi
LIBRARY_PATH=$PWD/../lib  PORTABLE=1 make shared_lib PLATFORM_SHARED_VERSIONED=false EXTRA_CXXFLAGS="-fPIC -I../include" EXTRA_CFLAGS="-fPIC" USE_RTTI=0 DEBUG_LEVEL=0 -j4
strip --strip-debug librocksdb.so
cp librocksdb.so ../lib/
PORTABLE=1 make PREFIX="$PWD/.." DEBUG_LEVEL=0 install-headers
cd ..
rm -rf rocksdb-6.29.fb rocksdb-6.29.fb.tar.gz
