#!/bin/bash

cd /opt

# check OS version
if ls /etc/redhat-release
then
  if [[ $(< /etc/redhat-release) == "CentOS release 5"* ]]
  then
    # CentOS 5
    # install cmake
    curl -L https://cmake.org/files/v3.12/cmake-3.12.3.tar.gz -o cmake-3.12.3.tar.gz
    tar zxvf cmake-3.12.3.tar.gz
    cd cmake-3.12.3
    ./bootstrap --prefix=/usr/local && make -j2 && make install
  else
    # CentOS 6+
    echo "CentOS 6+"
    yum install -y build-essential
  fi
else
  apt-get update
  apt-get install -y build-essential
fi

echo "Installing 3rd party libraries."

# zlib
cp aimrocks/deps/zlib/zlib-1.2.11.tar.gz .
tar zxvf zlib-1.2.11.tar.gz
cd zlib-1.2.11/
./configure && make CFLAGS='-fPIC' CXXFLAGS='-fPIC' && make install
cd ..
rm -rf zlib-1.2.11/ zlib-1.2.11.tar.gz

#bzip2
cp aimrocks/deps/bzip2/bzip2-1.0.8.tar.gz .
tar zxvf bzip2-1.0.8.tar.gz
cd bzip2-1.0.8/
make CFLAGS='-fPIC' CXXFLAGS='-fPIC' && make install
cd ..
rm -rf bzip2-1.0.8/ bzip2-1.0.8.tar.gz

# zstd
curl -L https://github.com/facebook/zstd/archive/v1.1.3.tar.gz -o zstd-1.1.3.tar.gz
tar zxvf zstd-1.1.3.tar.gz
cd zstd-1.1.3
make CFLAGS='-fPIC' CXXFLAGS='-fPIC' && make install
cd ..
rm -rf zstd-1.1.3 zstd-1.1.3.tar.gz

# lz4
curl -L  https://github.com/lz4/lz4/archive/v1.9.3.tar.gz -o lz4-1.9.3.tar.gz
tar zxvf lz4-1.9.3.tar.gz
cd lz4-1.9.3
make CFLAGS='-fPIC' CXXFLAGS='-fPIC' && make install
cd ..
rm -rf lz4-1.9.3 lz4-1.9.3.tar.gz

# snappy
curl -L https://github.com/google/snappy/archive/1.1.8.tar.gz -o snappy-1.1.8.tar.gz
tar zxvf snappy-1.1.8.tar.gz
cd snappy-1.1.8
mkdir build
cd build
cmake CFLAGS='-fPIC' CXXFLAGS='fPIC' -DCMAKE_POSITION_INDEPENDENT_CODE=ON .. && make && make install
cp libsnappy.a /usr/local/lib/
cd ../..
rm -rf snappy-1.1.8 snappy-1.1.8.tar.gz

#rocksdb static lib
curl -L https://github.com/facebook/rocksdb/archive/6.25.fb.tar.gz
mv 6.25.fb.tar.gz rocksdb-6.25.fb.tar.gz
tar zxvf rocksdb-6.25.fb.tar.gz
cd rocksdb-6.25.fb
EXTRA_CFLAGS="-DSNAPPY -I /usr/local/include/" EXTRA_CXXFLAGS="-DSNAPPY -I /usr/local/include/" PORTABLE=1 DEBUG_LEVEL=0 make -j2 shared_lib
EXTRA_CFLAGS="-DSNAPPY -I /usr/local/include/" EXTRA_CXXFLAGS="-DSNAPPY -I /usr/local/include/" PORTABLE=1 DEBUG_LEVEL=0 make static_lib
strip --strip-debug librocksdb.a
PORTABLE=1 DEBUG_LEVEL=0 make install-static
cd ..
rm -rf rocksdb-6.25.fb rocksdb-6.25.fb.tar.gz

echo "3rd party libraries install. SUCCESS"

cd /opt/aimrocks

echo "build python wheels"
for python_version in 'cp36-cp36m' 'cp37-cp37m' 'cp38-cp38' 'cp39-cp39' 'cp310-cp310'
do
  PYTHON_ROOT=/opt/python/${python_version}/
  if [ $python_version != "cp310-cp310" ]
  then
    # downgrade to pip-18
    $PYTHON_ROOT/bin/pip install --upgrade pip==18
  fi
  $PYTHON_ROOT/bin/python setup.py bdist_wheel -d linux_dist
  rm -rf build
done

for whl in $(ls ./linux_dist)
do
  auditwheel repair linux_dist/${whl} --wheel-dir multilinux_dist
done

echo "python wheels build. SUCCESS"
echo "DONE"
