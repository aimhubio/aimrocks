import os
import sys
import platform
from glob import glob
from setuptools import setup
from setuptools import find_packages
from setuptools import Extension
from distutils.dir_util import copy_tree
from distutils.file_util import copy_file


try:
    from Cython.Build import cythonize
except ImportError:
    print("Warning: Cython is not installed", file=sys.stderr)
    # Falling back to simpler build
    cythonize = lambda x: x


aimrocks_extra_compile_args = [
    '-std=c++11',
    '-O3',
    '-Wall',
    '-Wextra',
    '-Wconversion',
    '-fno-strict-aliasing',
    '-fno-rtti',
    '-fPIC',
]

aimrocks_extra_link_args = []

if platform.system() == 'Darwin':
    aimrocks_extra_compile_args += ['-mmacosx-version-min=10.7', '-stdlib=libc++']
    aimrocks_extra_link_args += ["-Wl,-rpath,@loader_path"]
else:
    aimrocks_extra_link_args += ["-Wl,-rpath,$ORIGIN"]

third_party_install_dir = os.environ.get('AIM_DEP_DIR', '/usr/local')
third_party_deps = ['rocksdb']

third_party_lib_dir = os.path.join(third_party_install_dir, 'lib')
third_party_libs = glob(os.path.join(third_party_lib_dir, 'librocksdb.*'))

third_party_headers = [os.path.join(third_party_install_dir, 'include/rocksdb')]

# We define a local include directory to store all the required public headers.
# The third party headers are copied into this directory to enable binding with
# the precompiled aimrocks binaries without third-party dependencies.
local_include_dir = os.path.abspath(
    os.path.join(os.path.dirname(__file__), 'src/aimrocks/include')
)
local_lib_dir = os.path.abspath(
    os.path.join(os.path.dirname(__file__), 'src/aimrocks')
)

print('third party libs detected:', third_party_libs)
for source in third_party_libs:
    print('copying third party lib', source, local_lib_dir)
    copy_file(source, local_lib_dir)

for source in third_party_headers:
    basename = os.path.basename(source)
    destination = os.path.join(local_include_dir, basename)
    copy_tree(source, destination,
              preserve_symlinks=False, update=True)


exts = [
    Extension(
        'aimrocks.lib_rocksdb',
        ['src/aimrocks/lib_rocksdb.pyx'],
        extra_compile_args=aimrocks_extra_compile_args,
        extra_link_args=aimrocks_extra_link_args,
        language='c++',
        include_dirs=[local_include_dir],
        library_dirs=[third_party_lib_dir],
        libraries=['rocksdb'],
    )
]


setup(
    name="aimrocks",
    version='0.2.0',
    description='RocksDB wrapper implemented in Cython.',
    setup_requires=['setuptools>=25', 'Cython>=3.0.0a9'],
    packages=find_packages('./src'),
    package_dir={'': 'src'},
    package_data={'aimrocks': ['src/*']},
    ext_modules=cythonize(exts),
    include_package_data=True,
    zip_safe=False,
)
