# content of test_sample.py
import aimrocks
import pytest
import shutil
import os
import tempfile

def test_open_skiplist_memtable_factory():
    opts = aimrocks.Options()
    opts.memtable_factory = aimrocks.SkipListMemtableFactory()
    opts.create_if_missing = True

    loc = tempfile.mkdtemp()
    try:
        test_db = aimrocks.DB(os.path.join(loc, "test"), opts)
    finally:
        del test_db
        shutil.rmtree(loc)


def test_open_vector_memtable_factory():
    opts = aimrocks.Options()
    opts.allow_concurrent_memtable_write = False
    opts.memtable_factory = aimrocks.VectorMemtableFactory()
    opts.create_if_missing = True
    loc = tempfile.mkdtemp()
    try:
        test_db = aimrocks.DB(os.path.join(loc, "test"), opts)
    finally:
        del test_db
        shutil.rmtree(loc)
