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
        'rocksdb'
    ]

def get_lib_filename(name):
    if platform.system() == 'Darwin':
        return f'lib{name}.dylib'
    else:
        return f'lib{name}.so'

def get_lib_file_paths():
    local_lib_dir = get_lib_dir()
    return [
        os.path.join(local_lib_dir, get_lib_filename(name))
        for name in get_libs()
    ]

def load_libs():
    if platform.system() == 'Darwin':
        return
    for path in get_lib_file_paths():
        ctypes.CDLL(path)
