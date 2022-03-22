#!/bin/bash

export AIM_DEP_DIR=/opt/aimrocks_deps

# check OS version
if [[ -f /etc/redhat-release ]]
then
  if [[ $(< /etc/redhat-release) == "CentOS release 5"* ]]
  then
    # CentOS 5
    export platform=centos_5
  fi
fi


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


for whl in dist/*.whl
do
  LD_LIBRARY_PATH=/opt/aimrocks_deps/lib:$LD_LIBRARY_PATH auditwheel repair ${whl} --wheel-dir manylinux_dist
done
rm -rf dist

echo "python wheels build. SUCCESS"
echo "DONE"
