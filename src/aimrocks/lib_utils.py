import os
import ctypes
import platform
from glob import glob


def get_include_dir():
    dirname = os.path.dirname(__file__)
    abs_dirname = os.path.abspath(dirname)
    path = os.path.join(abs_dirname, 'include')
    return path

def get_lib_dir():
    dirname = os.path.dirname(__file__)
    abs_dirname = os.path.abspath(dirname)
    path = abs_dirname
    return path

def get_libs():
    return [
        'rocksdb',
    ]

def get_lib_filename(name, lib_dir):
    if platform.system() == 'Darwin':
        pattern = f'lib{name}*.dylib'
    else:
        pattern = f'lib{name}*.so*'

    files = glob(os.path.join(lib_dir, pattern))
    assert len(files) == 1
    return os.path.basename(files[0])

def get_lib_filenames():
    local_lib_dir = get_lib_dir()
    return [
        get_lib_filename(name, local_lib_dir)
        for name in get_libs()
    ]

def load_lib(filename):
    local_lib_dir = get_lib_dir()
    path = os.path.join(local_lib_dir, filename)
    print(f'Loading runtime library from {path}')
    ctypes.CDLL(path)

def load_libs():
    for filename in get_lib_filenames():
        load_lib(filename)
