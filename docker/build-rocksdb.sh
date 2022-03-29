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

curl -L https://github.com/facebook/rocksdb/archive/6.29.fb.tar.gz -o rocksdb-6.29.fb.tar.gz
tar zxvf rocksdb-6.29.fb.tar.gz
cd rocksdb-6.29.fb
if [[ $platform == centos_5 ]]
then
  cp /opt/aimrocks_deps/rocksdb_sched.patch .
  patch port/port_posix.cc rocksdb_sched.patch
fi
PORTABLE=1 make shared_lib EXTRA_CXXFLAGS="-fPIC" EXTRA_CFLAGS="-fPIC" USE_RTTI=0 DEBUG_LEVEL=0 -j24
strip --strip-debug librocksdb.so
cp librocksdb.so.6.29 ../lib/
ln -s librocksdb.so.6.29 ../lib/librocksdb.so
PORTABLE=1 make PREFIX="../" DESTDIR="./" DEBUG_LEVEL=0 install-headers
cd ..
rm -rf rocksdb-6.29.fb rocksdb-6.29.fb.tar.gz
