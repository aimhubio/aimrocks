#!/bin/bash

cd /opt
cp -r /opt/aimrocks_ /opt/aimrocks

mkdir -p aimrocks_deps
export AIM_DEP_DIR=/opt/aimrocks_deps
cd aimrocks_deps/

mkdir -p lib
mkdir -p include

# check OS version
if [[ -f /etc/redhat-release ]]
then
  if [[ $(< /etc/redhat-release) == "CentOS release 5"* ]]
  then
    # CentOS 5
    export platform=centos_5
  fi
fi

/opt/python/cp35-cp35m/bin/python -m pip install cmake
ln -s /opt/python/cp35-cp35m/bin/cmake /usr/bin/cmake
PATH=/opt/python/cp35-cp35m/bin:$PATH


echo "Installing 3rd party libraries."

./build-zlib.sh
./build-bzip2.sh
./build-zstd.sh
./build-lz4.sh
./build-snappy.sh
./build-rocksdb.sh


echo "3rd party libraries install. SUCCESS"

cd /opt/aimrocks

echo "build python wheels"
python_versions=("cp36-cp36m" "cp37-cp37m" "cp38-cp38" "cp39-cp39")
if [[ $platform != centos_5 ]]
then
  python_versions+=("cp310-cp310")
fi

for python_version in "${python_versions[@]}"
do
  PYTHON_ROOT=/opt/python/${python_version}/
  $PYTHON_ROOT/bin/python -m pip install Cython==3.0.0a9
  $PYTHON_ROOT/bin/python -m build
  rm -rf build
done
