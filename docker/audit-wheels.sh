#!/bin/bash
set -e

export AIM_DEP_DIR=/opt/aimrocks_deps

# These libraries are manually handled
LIBS_BUNDLED=`ls ${AIM_DEP_DIR}/lib/ \
| grep .so \
| sed -r 's/^lib(.*?).so.*?$/\1/g' \
| uniq \
| paste -s -d','`
LD_LIBRARY_PATH=$AIM_DEP_DIR/lib:$LD_LIBRARY_PATH
INTERNAL_PYTHON=/opt/_internal/tools/bin/python

cd /opt/aimrocks

ls -lhatr dist

$INTERNAL_PYTHON -m pip install --upgrade pip
$INTERNAL_PYTHON -m pip uninstall -y auditwheel
$INTERNAL_PYTHON -m pip install git+https://github.com/aimhubio/auditwheel.git@include-exclude

for whl in dist/*.whl
do
  auditwheel repair ${whl} \
  --exclude $LIBS_BUNDLED \
  --wheel-dir manylinux_dist
done
rm -rf dist
