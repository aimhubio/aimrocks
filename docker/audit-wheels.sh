#!/bin/bash
set -e

export AIM_DEP_DIR=/opt/aimrocks_deps

# These libraries are manually handled
LIBS_BUNDLED=`ls ${AIM_DEP_DIR}/lib/ \
| grep .so \
| sed -r 's/^(lib.*?\.so)\.*?$/\1/g' \
| uniq \
| paste -s -d','`
export LD_LIBRARY_PATH=$AIM_DEP_DIR/lib:$LD_LIBRARY_PATH

INTERNAL_PYTHON=/opt/python/cp38-cp38/bin/python

cd /opt/aimrocks

ls -lhatr dist

$INTERNAL_PYTHON -m pip install --upgrade pip
$INTERNAL_PYTHON -m pip install git+https://github.com/aimhubio/auditwheel.git@include-exclude

for whl in dist/*.whl
do
  $INTERNAL_PYTHON -m auditwheel repair ${whl} \
  --exclude $LIBS_BUNDLED \
  --wheel-dir manylinux_dist
done
rm -rf dist
