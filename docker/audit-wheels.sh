#!/bin/bash
set -e

export AIM_DEP_DIR=/opt/aimrocks_deps

cd /opt/aimrocks

ls -lhatr dist

cp -r dist/*.shl manylinux_dist
rm -rf dist
