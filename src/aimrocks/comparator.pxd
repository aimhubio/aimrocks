from libcpp.string cimport string
from aimrocks.slice_ cimport Slice
from aimrocks.logger cimport Logger
from aimrocks.std_memory cimport shared_ptr

cdef extern from "rocksdb/comparator.h" namespace "rocksdb":
    cdef cppclass Comparator:
        const char* Name()
        int Compare(const Slice&, const Slice&) const

    cdef extern const Comparator* BytewiseComparator() nogil except +

ctypedef int (*compare_func)(
    void*,
    Logger*,
    string&,
    const Slice&,
    const Slice&)

cdef extern from "rdb_include/comparator_wrapper.hpp" namespace "py_rocks":
    cdef cppclass ComparatorWrapper:
        ComparatorWrapper(string, void*, compare_func) nogil except +
        void set_info_log(shared_ptr[Logger]) nogil except+
