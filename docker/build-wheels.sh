#!/bin/bash
set -e

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
python_versions=("cp36-cp36m" "cp37-cp37m" "cp38-cp38" "cp39-cp39" "cp310-cp310" "cp311-cp311" "cp312-cp312")

for python_version in "${python_versions[@]}"
do
  python_exe=/opt/python/${python_version}/bin/python
  if [ -f "$python_exe" ]
  then
    $python_exe -m build
    rm -rf build
  fi
done
