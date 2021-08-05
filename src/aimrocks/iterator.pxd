from libcpp cimport bool as cpp_bool
from aimrocks.slice_ cimport Slice
from aimrocks.status cimport Status

cdef extern from "rocksdb/iterator.h" namespace "rocksdb":
    cdef cppclass Iterator:
        cpp_bool Valid() nogil except+
        void SeekToFirst() nogil except+
        void SeekToLast() nogil except+
        void Seek(const Slice&) nogil except+
        void Next() nogil except+
        void Prev() nogil except+
        void SeekForPrev(const Slice&) nogil except+
        Slice key() nogil except+
        Slice value() nogil except+
        Status status() nogil except+
