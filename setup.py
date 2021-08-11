import os
import platform
from setuptools import setup
from setuptools import find_packages
from setuptools import Extension


aimrocks_extra_compile_args = [
    '-std=c++11',
    '-O3',
    '-Wall',
    '-Wextra',
    '-Wconversion',
    '-fno-strict-aliasing',
    '-fno-rtti',
]

if platform.system() == 'Darwin':
    aimrocks_extra_compile_args += ['-mmacosx-version-min=10.7', '-stdlib=libc++']

third_party_install_dir = '/usr/local'
third_party_deps = ['rocksdb', 'snappy', 'bz2', 'z', 'lz4', 'zstd']
third_party_libs = [os.path.join(third_party_install_dir, 'lib', 'lib{}.a'.format(lib)) for lib in third_party_deps]

setup(
    name="aimrocks",
    version='0.0.6rc2',
    description='RocksDB wrapper implemented in Cython.',
    setup_requires=['setuptools>=25', 'Cython==3.0.0a9'],
    packages=find_packages('./src'),
    package_dir={'': 'src'},
    ext_modules=[
        Extension(
            'aimrocks._rocksdb',
            ['src/aimrocks/_rocksdb.pyx'],
            extra_compile_args=aimrocks_extra_compile_args,
            language='c++',
            extra_objects=third_party_libs
        )
    ],
    include_package_data=True,
    zip_safe=False,
)
