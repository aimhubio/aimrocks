#!/bin/bash

export AIM_DEP_DIR=/opt/aimrocks_deps

cd /opt/aimrocks

for whl in dist/*.whl
do
  LD_LIBRARY_PATH=$AIM_DEP_DIR/lib:$LD_LIBRARY_PATH \
  auditwheel repair ${whl} \
  --wheel-dir manylinux_dist
done
rm -rf dist
