import os
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
    lib_dir = get_lib_dir()
    paths = glob(os.path.join(lib_dir, 'lib*.so'))
    return [
        os.path.basename(path)[3:-3] # strip `lib` and `.so`
        for path in paths
    ]
