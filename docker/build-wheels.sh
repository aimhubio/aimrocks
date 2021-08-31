#!/bin/bash

cd /opt

echo "Installing 3rd party libraries."

# check OS version
ls /etc/redhat-release
if [$? == 0]
then
  # CentOS
  yum install -y build-essential cmake wget
else
  apt-get update
  apt-get install -y build-essential cmake wget
fi

#rocksdb static lib
mkdir rocksdb && cd rocksdb
wget https://anaconda.org/conda-forge/rocksdb/6.13.3/download/linux-64/rocksdb-6.13.3-hda8cf21_2.tar.bz2
tar -xf rocksdb-6.13.3-hda8cf21_2.tar.bz2
cp lib/librocksdb.a /usr/local/lib/
cp -r include/rocksdb/ /usr/local/include/
cd ..
rm -rf rocksdb

# zlib
wget http://www.zlib.net/zlib-1.2.11.tar.gz
tar -xzf zlib-1.2.11.tar.gz
cd zlib-1.2.11/
./configure && make CFLAGS='-fPIC' CXXFLAGS='-fPIC' && make install
cd ..
rm -rf zlib-1.2.11/ zlib-1.2.11.tar.gz

#bzip2
wget https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
tar -xzf bzip2-1.0.8.tar.gz
cd bzip2-1.0.8/
make CFLAGS='-fPIC' CXXFLAGS='-fPIC' && make install
cd ..
rm -rf bzip2-1.0.8/ bzip2-1.0.8.tar.gz

# zstd
wget https://github.com/facebook/zstd/archive/v1.1.3.tar.gz
mv v1.1.3.tar.gz zstd-1.1.3.tar.gz
tar zxvf zstd-1.1.3.tar.gz
cd zstd-1.1.3
make CFLAGS='-fPIC' CXXFLAGS='-fPIC' && make install
cd ..
rm -rf zstd-1.1.3 zstd-1.1.3.tar.gz

# lz4
wget https://github.com/lz4/lz4/archive/v1.9.3.tar.gz
mv v1.9.3.tar.gz lz4-1.9.3.tar.gz
tar zxvf lz4-1.9.3.tar.gz
cd lz4-1.9.3
make CFLAGS='-fPIC' CXXFLAGS='-fPIC' && make install
cd ..
rm -rf lz4-1.9.3 lz4-1.9.3.tar.gz

# snappy
wget https://github.com/google/snappy/archive/1.1.8.tar.gz
mv 1.1.8.tar.gz snappy-1.1.8.tar.gz
tar zxvf snappy-1.1.8.tar.gz
cd snappy-1.1.8
mkdir build
cd build
cmake CFLAGS='-fPIC' CXXFLAGS='fPIC' -DCMAKE_POSITION_INDEPENDENT_CODE=ON .. && make
cp libsnappy.a /usr/local/lib/
cd ../..
rm -rf snappy-1.1.8 snappy-1.1.8.tar.gz

echo "3rd party libraries install. SUCCESS"

cd /opt/aimrocks

echo "build python wheels"
for python_version in 'cp36-cp36m' 'cp37-cp37m' 'cp38-cp38' 'cp39-cp39' 'cp310-cp310'
do
  PYTHON_ROOT=/opt/python/${python_version}/
  # downgrade to pip-18
  $PYTHON_ROOT/bin/pip install --upgrade pip==18
  $PYTHON_ROOT/bin/python setup.py bdist_wheel -d linux_dist
  rm -rf build
done

for whl in $(ls ./linux_dist)
do
  auditwheel repair linux_dist/${whl} --wheel-dir multilinux_dist
done

echo "python wheels build. SUCCESS"
echo "DONE"
