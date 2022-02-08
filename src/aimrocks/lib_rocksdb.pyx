# distutils: language = c++
# distutils: language_level = 3
import cython
from libcpp.string cimport string
from libcpp.deque cimport deque
from libcpp.vector cimport vector
from cpython cimport bool as py_bool
from libcpp cimport bool as cpp_bool
from libc.stdint cimport uint32_t
from cython.operator cimport dereference as deref
from cpython.bytes cimport PyBytes_AsString
from cpython.bytes cimport PyBytes_Size
from cpython.bytes cimport PyBytes_FromString
from cpython.bytes cimport PyBytes_FromStringAndSize
from cpython.unicode cimport PyUnicode_Decode

from aimrocks.std_memory cimport shared_ptr
cimport aimrocks.options as options
cimport aimrocks.merge_operator as merge_operator
cimport aimrocks.filter_policy as filter_policy
cimport aimrocks.comparator as comparator
cimport aimrocks.slice_transform as slice_transform
cimport aimrocks.cache as cache
cimport aimrocks.logger as logger
cimport aimrocks.snapshot as snapshot
cimport aimrocks.db as db
cimport aimrocks.iterator as iterator
cimport aimrocks.backup as backup
cimport aimrocks.env as env
cimport aimrocks.table_factory as table_factory
cimport aimrocks.memtablerep as memtablerep
cimport aimrocks.universal_compaction as universal_compaction

# Enums are the only exception for direct imports
# Their name als already unique enough
from aimrocks.universal_compaction cimport kCompactionStopStyleSimilarSize
from aimrocks.universal_compaction cimport kCompactionStopStyleTotalSize

from aimrocks.options cimport FlushOptions
from aimrocks.options cimport kCompactionStyleLevel
from aimrocks.options cimport kCompactionStyleUniversal
from aimrocks.options cimport kCompactionStyleFIFO
from aimrocks.options cimport kCompactionStyleNone

from aimrocks.slice_ cimport Slice
from aimrocks.status cimport Status

import sys
from aimrocks.interfaces import MergeOperator as IMergeOperator
from aimrocks.interfaces import AssociativeMergeOperator as IAssociativeMergeOperator
from aimrocks.interfaces import FilterPolicy as IFilterPolicy
from aimrocks.interfaces import Comparator as IComparator
from aimrocks.interfaces import SliceTransform as ISliceTransform
import traceback
import aimrocks.errors as errors
import weakref

# pxd defines:
# ctypedef const filter_policy.FilterPolicy ConstFilterPolicy

cdef extern from "rdb_include/utils.hpp" namespace "py_rocks":
    cdef const Slice* vector_data(vector[Slice]&)

# Prepare python for threaded usage.
# Python callbacks (merge, comparator)
# could be executed in a rocksdb background thread (eg. compaction).
cdef extern from "Python.h":
    void PyEval_InitThreads()
PyEval_InitThreads()

## Here comes the stuff to wrap the status to exception
cdef check_status(const Status& st):
    if st.ok():
        return

    if st.IsNotFound():
        raise errors.NotFound(st.ToString())

    if st.IsCorruption():
        raise errors.Corruption(st.ToString())

    if st.IsNotSupported():
        raise errors.NotSupported(st.ToString())

    if st.IsInvalidArgument():
        raise errors.InvalidArgument(st.ToString())

    if st.IsIOError():
        raise errors.RocksIOError(st.ToString())

    if st.IsMergeInProgress():
        raise errors.MergeInProgress(st.ToString())

    if st.IsIncomplete():
        raise errors.Incomplete(st.ToString())

    raise Exception("Unknown error: %s" % st.ToString())
######################################################


cdef string bytes_to_string(path) except *:
    return string(PyBytes_AsString(path), PyBytes_Size(path))

cdef string_to_bytes(string ob):
    return PyBytes_FromStringAndSize(ob.c_str(), ob.size())

cdef Slice bytes_to_slice(ob) except *:
    return Slice(PyBytes_AsString(ob), PyBytes_Size(ob))

cdef slice_to_bytes(Slice sl):
    return PyBytes_FromStringAndSize(sl.data(), sl.size())

## only for filsystem paths
cdef string path_to_string(object path) except *:
    if isinstance(path, bytes):
        return bytes_to_string(path)
    if isinstance(path, unicode):
        path = path.encode(sys.getfilesystemencoding())
        return bytes_to_string(path)
    else:
       raise TypeError("Wrong type for path: %s" % path)

cdef object string_to_path(string path):
    fs_encoding = sys.getfilesystemencoding().encode('ascii')
    return PyUnicode_Decode(path.c_str(), path.size(), fs_encoding, "replace")

## Here comes the stuff for the comparator
cdef class PyComparator(object):
    cdef object get_ob(self):
        return None

    cdef const comparator.Comparator* get_comparator(self):
        return NULL

    cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
        pass


cdef class PyGenericComparator(PyComparator):
    # pxd defines:
    # cdef comparator.ComparatorWrapper* comparator_ptr
    # cdef object ob

    def __cinit__(self, object ob):
        self.comparator_ptr = NULL
        if not isinstance(ob, IComparator):
            raise TypeError("%s is not of type %s" % (ob, IComparator))

        self.ob = ob
        self.comparator_ptr = new comparator.ComparatorWrapper(
                bytes_to_string(ob.name()),
                <void*>ob,
                compare_callback)

    def __dealloc__(self):
        if not self.comparator_ptr == NULL:
            del self.comparator_ptr

    cdef object get_ob(self):
        return self.ob

    cdef const comparator.Comparator* get_comparator(self):
        return <comparator.Comparator*> self.comparator_ptr

    cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
        self.comparator_ptr.set_info_log(info_log)


cdef class PyBytewiseComparator(PyComparator):
    # pxd defines:
    # cdef const comparator.Comparator* comparator_ptr

    def __cinit__(self):
        self.comparator_ptr = comparator.BytewiseComparator()

    cpdef name(self):
        return PyBytes_FromString(self.comparator_ptr.Name())

    cpdef compare(self, a, b):
        return self.comparator_ptr.Compare(
            bytes_to_slice(a),
            bytes_to_slice(b))

    cdef object get_ob(self):
       return self

    cdef const comparator.Comparator* get_comparator(self):
        return self.comparator_ptr



cdef int compare_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice& a,
    const Slice& b) with gil:

    try:
        return (<object>ctx).compare(slice_to_bytes(a), slice_to_bytes(b))
    except BaseException as error:
        tb = traceback.format_exc()
        logger.Log(log, "Error in compare callback: %s", <bytes>tb)
        error_msg.assign(<bytes>str(error))

BytewiseComparator = PyBytewiseComparator
#########################################



## Here comes the stuff for the filter policy
cdef class PyFilterPolicy(object):
    cdef object get_ob(self):
        return None

    cdef shared_ptr[ConstFilterPolicy] get_policy(self):
        return shared_ptr[ConstFilterPolicy]()

    cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
        pass


cdef class PyGenericFilterPolicy(PyFilterPolicy):
    # pxd defines:
    # cdef shared_ptr[filter_policy.FilterPolicyWrapper] policy
    # cdef object ob

    def __cinit__(self, object ob):
        if not isinstance(ob, IFilterPolicy):
            raise TypeError("%s is not of type %s" % (ob, IFilterPolicy))

        self.ob = ob
        self.policy.reset(new filter_policy.FilterPolicyWrapper(
                bytes_to_string(ob.name()),
                <void*>ob,
                create_filter_callback,
                key_may_match_callback))

    cdef object get_ob(self):
        return self.ob

    cdef shared_ptr[ConstFilterPolicy] get_policy(self):
        return <shared_ptr[ConstFilterPolicy]>(self.policy)

    cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
        self.policy.get().set_info_log(info_log)


cdef void create_filter_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice* keys,
    int n,
    string* dst) with gil:

    try:
        ret = (<object>ctx).create_filter(
            [slice_to_bytes(keys[i]) for i in range(n)])
        dst.append(bytes_to_string(ret))
    except BaseException as error:
        tb = traceback.format_exc()
        logger.Log(log, "Error in create filter callback: %s", <bytes>tb)
        error_msg.assign(<bytes>str(error))

cdef cpp_bool key_may_match_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice& key,
    const Slice& filt) with gil:

    try:
        return (<object>ctx).key_may_match(
            slice_to_bytes(key),
            slice_to_bytes(filt))
    except BaseException as error:
        tb = traceback.format_exc()
        logger.Log(log, "Error in key_mach_match callback: %s", <bytes>tb)
        error_msg.assign(<bytes>str(error))


cdef class PyBloomFilterPolicy(PyFilterPolicy):
    # pxd defines:
    # cdef shared_ptr[ConstFilterPolicy] policy

    def __cinit__(self, int bits_per_key):
        self.policy.reset(filter_policy.NewBloomFilterPolicy(bits_per_key))

    cpdef name(self):
        return PyBytes_FromString(self.policy.get().Name())

    cpdef create_filter(self, keys):
        cdef string dst
        cdef vector[Slice] c_keys

        for key in keys:
            c_keys.push_back(bytes_to_slice(key))

        self.policy.get().CreateFilter(
            vector_data(c_keys),
            <int>c_keys.size(),
            cython.address(dst))

        return string_to_bytes(dst)

    cpdef key_may_match(self, key, filter_):
        return self.policy.get().KeyMayMatch(
            bytes_to_slice(key),
            bytes_to_slice(filter_))

    cdef object get_ob(self):
        return self

    cdef shared_ptr[ConstFilterPolicy] get_policy(self):
        return self.policy

BloomFilterPolicy = PyBloomFilterPolicy
#############################################



## Here comes the stuff for the merge operator
cdef class PyMergeOperator(object):
    # pxd defines:
    # cdef shared_ptr[merge_operator.MergeOperator] merge_op
    # cdef object ob

    def __cinit__(self, object ob):
        self.ob = ob
        if isinstance(ob, IAssociativeMergeOperator):
            self.merge_op.reset(
                <merge_operator.MergeOperator*>
                    new merge_operator.AssociativeMergeOperatorWrapper(
                        bytes_to_string(ob.name()),
                        <void*>(ob),
                        merge_callback))

        elif isinstance(ob, IMergeOperator):
            self.merge_op.reset(
                <merge_operator.MergeOperator*>
                    new merge_operator.MergeOperatorWrapper(
                        bytes_to_string(ob.name()),
                        <void*>ob,
                        <void*>ob,
                        full_merge_callback,
                        partial_merge_callback))
        #  elif isinstance(ob, str):
            #  if ob == "put":
              #  self.merge_op = merge_operator.MergeOperators.CreatePutOperator()
            #  elif ob == "put_v1":
              #  self.merge_op = merge_operator.MergeOperators.CreateDeprecatedPutOperator()
            #  elif ob == "uint64add":
              #  self.merge_op = merge_operator.MergeOperators.CreateUInt64AddOperator()
            #  elif ob == "stringappend":
              #  self.merge_op = merge_operator.MergeOperators.CreateStringAppendOperator()
            #  #TODO: necessary?
            #  #  elif ob == "stringappendtest":
              #  #  self.merge_op = merge_operator.MergeOperators.CreateStringAppendTESTOperator()
            #  elif ob == "max":
              #  self.merge_op = merge_operator.MergeOperators.CreateMaxOperator()
            #  else:
                #  msg = "{0} is not the default type".format(ob)
                #  raise TypeError(msg)
        else:
            msg = "%s is not of this types %s"
            msg %= (ob, (IAssociativeMergeOperator, IMergeOperator))
            raise TypeError(msg)


    cdef object get_ob(self):
        return self.ob

    cdef shared_ptr[merge_operator.MergeOperator] get_operator(self):
        return self.merge_op

cdef cpp_bool merge_callback(
    void* ctx,
    const Slice& key,
    const Slice* existing_value,
    const Slice& value,
    string* new_value,
    logger.Logger* log) with gil:

    if existing_value == NULL:
        py_existing_value = None
    else:
        py_existing_value = slice_to_bytes(deref(existing_value))

    try:
        ret = (<object>ctx).merge(
            slice_to_bytes(key),
            py_existing_value,
            slice_to_bytes(value))

        if ret[0]:
            new_value.assign(bytes_to_string(ret[1]))
            return True
        return False

    except:
        tb = traceback.format_exc()
        logger.Log(log, "Error in merge_callback: %s", <bytes>tb)
        return False

cdef cpp_bool full_merge_callback(
    void* ctx,
    const Slice& key,
    const Slice* existing_value,
    const deque[string]& op_list,
    string* new_value,
    logger.Logger* log) with gil:

    if existing_value == NULL:
        py_existing_value = None
    else:
        py_existing_value = slice_to_bytes(deref(existing_value))

    try:
        ret = (<object>ctx).full_merge(
            slice_to_bytes(key),
            py_existing_value,
            [string_to_bytes(op_list[i]) for i in range(op_list.size())])

        if ret[0]:
            new_value.assign(bytes_to_string(ret[1]))
            return True
        return False

    except:
        tb = traceback.format_exc()
        logger.Log(log, "Error in full_merge_callback: %s", <bytes>tb)
        return False

cdef cpp_bool partial_merge_callback(
    void* ctx,
    const Slice& key,
    const Slice& left_op,
    const Slice& right_op,
    string* new_value,
    logger.Logger* log) with gil:

    try:
        ret = (<object>ctx).partial_merge(
            slice_to_bytes(key),
            slice_to_bytes(left_op),
            slice_to_bytes(right_op))

        if ret[0]:
            new_value.assign(bytes_to_string(ret[1]))
            return True
        return False

    except:
        tb = traceback.format_exc()
        logger.Log(log, "Error in partial_merge_callback: %s", <bytes>tb)
        return False
##############################################

#### Here comes the Cache stuff
cdef class PyCache(object):
    cdef shared_ptr[cache.Cache] get_cache(self):
        return shared_ptr[cache.Cache]()


cdef class PyLRUCache(PyCache):
    # pxd defines:
    # cdef shared_ptr[cache.Cache] cache_ob

    def __cinit__(self, capacity, shard_bits=None):
        if shard_bits is not None:
            self.cache_ob = cache.NewLRUCache(capacity, shard_bits)
        else:
            self.cache_ob = cache.NewLRUCache(capacity)

    cdef shared_ptr[cache.Cache] get_cache(self):
        return self.cache_ob

LRUCache = PyLRUCache
###############################

### Here comes the stuff for SliceTransform
cdef class PySliceTransform(object):
    # pxd defines:
    # cdef shared_ptr[slice_transform.SliceTransform] transfomer
    # cdef object ob

    def __cinit__(self, object ob):
        if not isinstance(ob, ISliceTransform):
            raise TypeError("%s is not of type %s" % (ob, ISliceTransform))

        self.ob = ob
        self.transfomer.reset(
            <slice_transform.SliceTransform*>
                new slice_transform.SliceTransformWrapper(
                    bytes_to_string(ob.name()),
                    <void*>ob,
                    slice_transform_callback,
                    slice_in_domain_callback,
                    slice_in_range_callback))

    cdef object get_ob(self):
        return self.ob

    cdef shared_ptr[slice_transform.SliceTransform] get_transformer(self):
        return self.transfomer

    cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
        cdef slice_transform.SliceTransformWrapper* ptr
        ptr = <slice_transform.SliceTransformWrapper*> self.transfomer.get()
        ptr.set_info_log(info_log)


cdef Slice slice_transform_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice& src) with gil:

    cdef size_t offset
    cdef size_t size

    try:
        ret = (<object>ctx).transform(slice_to_bytes(src))
        offset = ret[0]
        size = ret[1]
        if (offset + size) > src.size():
            msg = "offset(%i) + size(%i) is bigger than slice(%i)"
            raise Exception(msg  % (offset, size, src.size()))

        return Slice(src.data() + offset, size)
    except BaseException as error:
        tb = traceback.format_exc()
        logger.Log(log, "Error in slice transfrom callback: %s", <bytes>tb)
        error_msg.assign(<bytes>str(error))

cdef cpp_bool slice_in_domain_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice& src) with gil:

    try:
        return (<object>ctx).in_domain(slice_to_bytes(src))
    except BaseException as error:
        tb = traceback.format_exc()
        logger.Log(log, "Error in slice transfrom callback: %s", <bytes>tb)
        error_msg.assign(<bytes>str(error))

cdef cpp_bool slice_in_range_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice& src) with gil:

    try:
        return (<object>ctx).in_range(slice_to_bytes(src))
    except BaseException as error:
        tb = traceback.format_exc()
        logger.Log(log, "Error in slice transfrom callback: %s", <bytes>tb)
        error_msg.assign(<bytes>str(error))
###########################################


## Here are the TableFactories
cdef class PyTableFactory(object):
    # pxd defines:
    # cdef shared_ptr[table_factory.TableFactory] factory

    cdef shared_ptr[table_factory.TableFactory] get_table_factory(self):
        return self.factory

    cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
        pass


cdef class BlockBasedTableFactory(PyTableFactory):
    # pxd defines:
    # cdef PyFilterPolicy py_filter_policy

    def __init__(self,
            index_type='binary_search',
            py_bool hash_index_allow_collision=True,
            checksum='crc32',
            PyCache block_cache=None,
            PyCache block_cache_compressed=None,
            filter_policy=None,
            no_block_cache=False,
            block_size=None,
            block_size_deviation=None,
            block_restart_interval=None,
            whole_key_filtering=None):

        cdef table_factory.BlockBasedTableOptions table_options

        if index_type == 'binary_search':
            table_options.index_type = table_factory.kBinarySearch
        elif index_type == 'hash_search':
            table_options.index_type = table_factory.kHashSearch
        else:
            raise ValueError("Unknown index_type: %s" % index_type)

        if hash_index_allow_collision:
            table_options.hash_index_allow_collision = True
        else:
            table_options.hash_index_allow_collision = False

        if checksum == 'crc32':
            table_options.checksum = table_factory.kCRC32c
        elif checksum == 'xxhash':
            table_options.checksum = table_factory.kxxHash
        else:
            raise ValueError("Unknown checksum: %s" % checksum)

        if no_block_cache:
            table_options.no_block_cache = True
        else:
            table_options.no_block_cache = False

        # If the following options are None use the rocksdb default.
        if block_size is not None:
            table_options.block_size = block_size

        if block_size_deviation is not None:
            table_options.block_size_deviation = block_size_deviation

        if block_restart_interval is not None:
            table_options.block_restart_interval = block_restart_interval

        if whole_key_filtering is not None:
            if whole_key_filtering:
                table_options.whole_key_filtering = True
            else:
                table_options.whole_key_filtering = False

        if block_cache is not None:
            table_options.block_cache = block_cache.get_cache()

        if block_cache_compressed is not None:
            table_options.block_cache_compressed = block_cache_compressed.get_cache()

        # Set the filter_policy
        self.py_filter_policy = None
        if filter_policy is not None:
            if isinstance(filter_policy, PyFilterPolicy):
                if (<PyFilterPolicy?>filter_policy).get_policy().get() == NULL:
                    raise Exception("Cannot set filter policy: %s" % filter_policy)
                self.py_filter_policy = filter_policy
            else:
                self.py_filter_policy = PyGenericFilterPolicy(filter_policy)

            table_options.filter_policy = self.py_filter_policy.get_policy()

        self.factory.reset(table_factory.NewBlockBasedTableFactory(table_options))

    cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
        if self.py_filter_policy is not None:
            self.py_filter_policy.set_info_log(info_log)


cdef class PlainTableFactory(PyTableFactory):
    def __init__(
            self,
            user_key_len=0,
            bloom_bits_per_key=10,
            hash_table_ratio=0.75,
            index_sparseness=10,
            huge_page_tlb_size=0,
            encoding_type='plain',
            py_bool full_scan_mode=False):

        cdef table_factory.PlainTableOptions table_options

        table_options.user_key_len = user_key_len
        table_options.bloom_bits_per_key = bloom_bits_per_key
        table_options.hash_table_ratio = hash_table_ratio
        table_options.index_sparseness = index_sparseness
        table_options.huge_page_tlb_size = huge_page_tlb_size

        if encoding_type == 'plain':
            table_options.encoding_type = table_factory.kPlain
        elif encoding_type == 'prefix':
            table_options.encoding_type = table_factory.kPrefix
        else:
            raise ValueError("Unknown encoding_type: %s" % encoding_type)

        table_options.full_scan_mode = full_scan_mode

        self.factory.reset( table_factory.NewPlainTableFactory(table_options))
#############################################


### Here are the MemtableFactories
cdef class PyMemtableFactory(object):
    # pxd defines:
    # cdef shared_ptr[memtablerep.MemTableRepFactory] factory

    cdef shared_ptr[memtablerep.MemTableRepFactory] get_memtable_factory(self):
        return self.factory


cdef class SkipListMemtableFactory(PyMemtableFactory):
    def __init__(self):
        self.factory.reset(memtablerep.NewSkipListFactory())


cdef class VectorMemtableFactory(PyMemtableFactory):
    def __init__(self, count=0):
        self.factory.reset(memtablerep.NewVectorRepFactory(count))


cdef class HashSkipListMemtableFactory(PyMemtableFactory):
    def __init__(
            self,
            bucket_count=1000000,
            skiplist_height=4,
            skiplist_branching_factor=4):

        self.factory.reset(
            memtablerep.NewHashSkipListRepFactory(
                bucket_count,
                skiplist_height,
                skiplist_branching_factor))


cdef class HashLinkListMemtableFactory(PyMemtableFactory):
    def __init__(self, bucket_count=50000):
        self.factory.reset(memtablerep.NewHashLinkListRepFactory(bucket_count))
##################################


cdef class CompressionType(object):
    no_compression = u'no_compression'
    snappy_compression = u'snappy_compression'
    zlib_compression = u'zlib_compression'
    bzip2_compression = u'bzip2_compression'
    lz4_compression = u'lz4_compression'
    lz4hc_compression = u'lz4hc_compression'
    xpress_compression = u'xpress_compression'
    zstd_compression = u'zstd_compression'
    zstdnotfinal_compression = u'zstdnotfinal_compression'
    disable_compression = u'disable_compression'

cdef class CompactionPri(object):
    by_compensated_size = u'by_compensated_size'
    oldest_largest_seq_first = u'oldest_largest_seq_first'
    oldest_smallest_seq_first = u'oldest_smallest_seq_first'
    min_overlapping_ratio = u'min_overlapping_ratio'


cdef class _ColumnFamilyHandle:
    """ This is an internal class that we will weakref for safety """
    # pxd defines:
    # cdef db.ColumnFamilyHandle* handle
    # cdef object __weakref__
    # cdef object weak_handle

    def __cinit__(self):
        self.handle = NULL

    def __dealloc__(self):
        if not self.handle == NULL:
            del self.handle

    @staticmethod
    cdef from_handle_ptr(db.ColumnFamilyHandle* handle):
        inst = <_ColumnFamilyHandle>_ColumnFamilyHandle.__new__(_ColumnFamilyHandle)
        inst.handle = handle
        return inst

    @property
    def name(self):
        return self.handle.GetName()

    @property
    def id(self):
        return self.handle.GetID()

    @property
    def weakref(self):
        if self.weak_handle is None:
            self.weak_handle = ColumnFamilyHandle.from_wrapper(self)
        return self.weak_handle

cdef class ColumnFamilyHandle:
    """ This represents a ColumnFamilyHandle """
    # cdef object _ref
    # cdef readonly bytes name
    # cdef readonly int id

    def __cinit__(self, weakhandle):
        self._ref = weakhandle
        self.name = self._ref().name
        self.id = self._ref().id

    def __init__(self, *):
        raise TypeError("These can not be constructed from Python")

    @staticmethod
    cdef object from_wrapper(_ColumnFamilyHandle real_handle):
        return ColumnFamilyHandle.__new__(ColumnFamilyHandle, weakref.ref(real_handle))

    @property
    def is_valid(self):
        return self._ref() is not None

    def __repr__(self):
        valid = "valid" if self.is_valid else "invalid"
        return f"<ColumnFamilyHandle name: {self.name}, id: {self.id}, state: {valid}>"

    cdef db.ColumnFamilyHandle* get_handle(self) except NULL:
        cdef _ColumnFamilyHandle real_handle = self._ref()
        if real_handle is None:
            raise ValueError(f"{self} is no longer a valid ColumnFamilyHandle!")
        return real_handle.handle

    def __eq__(self, other):
        cdef ColumnFamilyHandle fast_other
        if isinstance(other, ColumnFamilyHandle):
            fast_other = other
            return (
                self.name == fast_other.name
                and self.id == fast_other.id
                and self._ref == fast_other._ref
            )
        return False

    def __lt__(self, other):
        cdef ColumnFamilyHandle fast_other
        if isinstance(other, ColumnFamilyHandle):
            return self.id < other.id
        return NotImplemented

    # Since @total_ordering isn't a thing for cython
    def __ne__(self, other):
        return not self == other

    def __gt__(self, other):
        return other < self

    def __le__(self, other):
        return not other < self

    def __ge__(self, other):
        return not self < other

    def __hash__(self):
        # hash of a weakref matches that of its original ref'ed object
        # so we use the id of our weakref object here to prevent
        # a situation where we are invalid, but match a valid handle's hash
        return hash((self.id, self.name, id(self._ref)))


cdef class ColumnFamilyOptions(object):
    # pxd defines:
    # cdef options.ColumnFamilyOptions* copts
    # cdef PyComparator py_comparator
    # cdef PyMergeOperator py_merge_operator
    # cdef PySliceTransform py_prefix_extractor
    # cdef PyTableFactory py_table_factory
    # cdef PyMemtableFactory py_memtable_factory
    # cdef cpp_bool in_use

    def __cinit__(self):
        self.copts = NULL
        self.copts = new options.ColumnFamilyOptions()
        self.in_use = False

    def __dealloc__(self):
        if not self.copts == NULL:
            del self.copts

    def __init__(self, **kwargs):
        self.py_comparator = BytewiseComparator()
        self.py_merge_operator = None
        self.py_prefix_extractor = None
        self.py_table_factory = None
        self.py_memtable_factory = None

        for key, value in kwargs.items():
            setattr(self, key, value)

    property write_buffer_size:
        def __get__(self):
            return self.copts.write_buffer_size
        def __set__(self, value):
            self.copts.write_buffer_size = value

    property max_write_buffer_number:
        def __get__(self):
            return self.copts.max_write_buffer_number
        def __set__(self, value):
            self.copts.max_write_buffer_number = value

    property min_write_buffer_number_to_merge:
        def __get__(self):
            return self.copts.min_write_buffer_number_to_merge
        def __set__(self, value):
            self.copts.min_write_buffer_number_to_merge = value

    property compression_opts:
        def __get__(self):
            cdef dict ret_ob = {}

            ret_ob['window_bits'] = self.copts.compression_opts.window_bits
            ret_ob['level'] = self.copts.compression_opts.level
            ret_ob['strategy'] = self.copts.compression_opts.strategy
            ret_ob['max_dict_bytes'] = self.copts.compression_opts.max_dict_bytes

            return ret_ob

        def __set__(self, dict value):
            cdef options.CompressionOptions* copts
            copts = cython.address(self.copts.compression_opts)
            #  CompressionOptions(int wbits, int _lev, int _strategy, int _max_dict_bytes)
            if 'window_bits' in value:
                copts.window_bits  = value['window_bits']
            if 'level' in value:
                copts.level = value['level']
            if 'strategy' in value:
                copts.strategy = value['strategy']
            if 'max_dict_bytes' in value:
                copts.max_dict_bytes = value['max_dict_bytes']

    property compaction_pri:
        def __get__(self):
            if self.copts.compaction_pri == options.kByCompensatedSize:
                return CompactionPri.by_compensated_size
            if self.copts.compaction_pri == options.kOldestLargestSeqFirst:
                return CompactionPri.oldest_largest_seq_first
            if self.copts.compaction_pri == options.kOldestSmallestSeqFirst:
                return CompactionPri.oldest_smallest_seq_first
            if self.copts.compaction_pri == options.kMinOverlappingRatio:
                return CompactionPri.min_overlapping_ratio
        def __set__(self, value):
            if value == CompactionPri.by_compensated_size:
                self.copts.compaction_pri = options.kByCompensatedSize
            elif value == CompactionPri.oldest_largest_seq_first:
                self.copts.compaction_pri = options.kOldestLargestSeqFirst
            elif value == CompactionPri.oldest_smallest_seq_first:
                self.copts.compaction_pri = options.kOldestSmallestSeqFirst
            elif value == CompactionPri.min_overlapping_ratio:
                self.copts.compaction_pri = options.kMinOverlappingRatio
            else:
                raise TypeError("Unknown compaction pri: %s" % value)

    property compression:
        def __get__(self):
            if self.copts.compression == options.kNoCompression:
                return CompressionType.no_compression
            elif self.copts.compression  == options.kSnappyCompression:
                return CompressionType.snappy_compression
            elif self.copts.compression == options.kZlibCompression:
                return CompressionType.zlib_compression
            elif self.copts.compression == options.kBZip2Compression:
                return CompressionType.bzip2_compression
            elif self.copts.compression == options.kLZ4Compression:
                return CompressionType.lz4_compression
            elif self.copts.compression == options.kLZ4HCCompression:
                return CompressionType.lz4hc_compression
            elif self.copts.compression == options.kXpressCompression:
                return CompressionType.xpress_compression
            elif self.copts.compression == options.kZSTD:
                return CompressionType.zstd_compression
            elif self.copts.compression == options.kZSTDNotFinalCompression:
                return CompressionType.zstdnotfinal_compression
            elif self.copts.compression == options.kDisableCompressionOption:
                return CompressionType.disable_compression
            else:
                raise Exception("Unknonw type: %s" % self.opts.compression)

        def __set__(self, value):
            if value == CompressionType.no_compression:
                self.copts.compression = options.kNoCompression
            elif value == CompressionType.snappy_compression:
                self.copts.compression = options.kSnappyCompression
            elif value == CompressionType.zlib_compression:
                self.copts.compression = options.kZlibCompression
            elif value == CompressionType.bzip2_compression:
                self.copts.compression = options.kBZip2Compression
            elif value == CompressionType.lz4_compression:
                self.copts.compression = options.kLZ4Compression
            elif value == CompressionType.lz4hc_compression:
                self.copts.compression = options.kLZ4HCCompression
            elif value == CompressionType.zstd_compression:
                self.copts.compression = options.kZSTD
            elif value == CompressionType.zstdnotfinal_compression:
                self.copts.compression = options.kZSTDNotFinalCompression
            elif value == CompressionType.disable_compression:
                self.copts.compression = options.kDisableCompressionOption
            else:
                raise TypeError("Unknown compression: %s" % value)

    property max_compaction_bytes:
        def __get__(self):
            return self.copts.max_compaction_bytes
        def __set__(self, value):
            self.copts.max_compaction_bytes = value

    property num_levels:
        def __get__(self):
            return self.copts.num_levels
        def __set__(self, value):
            self.copts.num_levels = value

    property level0_file_num_compaction_trigger:
        def __get__(self):
            return self.copts.level0_file_num_compaction_trigger
        def __set__(self, value):
            self.copts.level0_file_num_compaction_trigger = value

    property level0_slowdown_writes_trigger:
        def __get__(self):
            return self.copts.level0_slowdown_writes_trigger
        def __set__(self, value):
            self.copts.level0_slowdown_writes_trigger = value

    property level0_stop_writes_trigger:
        def __get__(self):
            return self.copts.level0_stop_writes_trigger
        def __set__(self, value):
            self.copts.level0_stop_writes_trigger = value

    property max_mem_compaction_level:
        def __get__(self):
            return self.copts.max_mem_compaction_level
        def __set__(self, value):
            self.copts.max_mem_compaction_level = value

    property target_file_size_base:
        def __get__(self):
            return self.copts.target_file_size_base
        def __set__(self, value):
            self.copts.target_file_size_base = value

    property target_file_size_multiplier:
        def __get__(self):
            return self.copts.target_file_size_multiplier
        def __set__(self, value):
            self.copts.target_file_size_multiplier = value

    property max_bytes_for_level_base:
        def __get__(self):
            return self.copts.max_bytes_for_level_base
        def __set__(self, value):
            self.copts.max_bytes_for_level_base = value

    property max_bytes_for_level_multiplier:
        def __get__(self):
            return self.copts.max_bytes_for_level_multiplier
        def __set__(self, value):
            self.copts.max_bytes_for_level_multiplier = value

    property max_bytes_for_level_multiplier_additional:
        def __get__(self):
            return self.copts.max_bytes_for_level_multiplier_additional
        def __set__(self, value):
            self.copts.max_bytes_for_level_multiplier_additional = value

    property arena_block_size:
        def __get__(self):
            return self.copts.arena_block_size
        def __set__(self, value):
            self.copts.arena_block_size = value

    property disable_auto_compactions:
        def __get__(self):
            return self.copts.disable_auto_compactions
        def __set__(self, value):
            self.copts.disable_auto_compactions = value

    # FIXME: remove to util/options_helper.h
    #  property allow_os_buffer:
        #  def __get__(self):
            #  return self.copts.allow_os_buffer
        #  def __set__(self, value):
            #  self.copts.allow_os_buffer = value

    property compaction_style:
        def __get__(self):
            if self.copts.compaction_style == kCompactionStyleLevel:
                return 'level'
            if self.copts.compaction_style == kCompactionStyleUniversal:
                return 'universal'
            if self.copts.compaction_style == kCompactionStyleFIFO:
                return 'fifo'
            if self.copts.compaction_style == kCompactionStyleNone:
                return 'none'
            raise Exception("Unknown compaction_style")

        def __set__(self, str value):
            if value == 'level':
                self.copts.compaction_style = kCompactionStyleLevel
            elif value == 'universal':
                self.copts.compaction_style = kCompactionStyleUniversal
            elif value == 'fifo':
                self.copts.compaction_style = kCompactionStyleFIFO
            elif value == 'none':
                self.copts.compaction_style = kCompactionStyleNone
            else:
                raise Exception("Unknown compaction style")

    property compaction_options_universal:
        def __get__(self):
            cdef universal_compaction.CompactionOptionsUniversal uopts
            cdef dict ret_ob = {}

            uopts = self.copts.compaction_options_universal

            ret_ob['size_ratio'] = uopts.size_ratio
            ret_ob['min_merge_width'] = uopts.min_merge_width
            ret_ob['max_merge_width'] = uopts.max_merge_width
            ret_ob['max_size_amplification_percent'] = uopts.max_size_amplification_percent
            ret_ob['compression_size_percent'] = uopts.compression_size_percent

            if uopts.stop_style == kCompactionStopStyleSimilarSize:
                ret_ob['stop_style'] = 'similar_size'
            elif uopts.stop_style == kCompactionStopStyleTotalSize:
                ret_ob['stop_style'] = 'total_size'
            else:
                raise Exception("Unknown compaction style")

            return ret_ob

        def __set__(self, dict value):
            cdef universal_compaction.CompactionOptionsUniversal* uopts
            uopts = cython.address(self.copts.compaction_options_universal)

            if 'size_ratio' in value:
                uopts.size_ratio  = value['size_ratio']

            if 'min_merge_width' in value:
                uopts.min_merge_width = value['min_merge_width']

            if 'max_merge_width' in value:
                uopts.max_merge_width = value['max_merge_width']

            if 'max_size_amplification_percent' in value:
                uopts.max_size_amplification_percent = value['max_size_amplification_percent']

            if 'compression_size_percent' in value:
                uopts.compression_size_percent = value['compression_size_percent']

            if 'stop_style' in value:
                if value['stop_style'] == 'similar_size':
                    uopts.stop_style = kCompactionStopStyleSimilarSize
                elif value['stop_style'] == 'total_size':
                    uopts.stop_style = kCompactionStopStyleTotalSize
                else:
                    raise Exception("Unknown compaction style")

    # Deprecate
    #  property filter_deletes:
        #  def __get__(self):
            #  return self.copts.filter_deletes
        #  def __set__(self, value):
            #  self.copts.filter_deletes = value

    property max_sequential_skip_in_iterations:
        def __get__(self):
            return self.copts.max_sequential_skip_in_iterations
        def __set__(self, value):
            self.copts.max_sequential_skip_in_iterations = value

    property inplace_update_support:
        def __get__(self):
            return self.copts.inplace_update_support
        def __set__(self, value):
            self.copts.inplace_update_support = value

    property table_factory:
        def __get__(self):
            return self.py_table_factory

        def __set__(self, PyTableFactory value):
            self.py_table_factory = value
            self.copts.table_factory = value.get_table_factory()

    property memtable_factory:
        def __get__(self):
            return self.py_memtable_factory

        def __set__(self, PyMemtableFactory value):
            self.py_memtable_factory = value
            self.copts.memtable_factory = value.get_memtable_factory()

    property inplace_update_num_locks:
        def __get__(self):
            return self.copts.inplace_update_num_locks
        def __set__(self, value):
            self.copts.inplace_update_num_locks = value

    property comparator:
        def __get__(self):
            return self.py_comparator.get_ob()

        def __set__(self, value):
            if isinstance(value, PyComparator):
                if (<PyComparator?>value).get_comparator() == NULL:
                    raise Exception("Cannot set %s as comparator" % value)
                else:
                    self.py_comparator = value
            else:
                self.py_comparator = PyGenericComparator(value)

            self.copts.comparator = self.py_comparator.get_comparator()

    property merge_operator:
        def __get__(self):
            if self.py_merge_operator is None:
                return None
            return self.py_merge_operator.get_ob()

        def __set__(self, value):
            self.py_merge_operator = PyMergeOperator(value)
            self.copts.merge_operator = self.py_merge_operator.get_operator()

    property prefix_extractor:
        def __get__(self):
            if self.py_prefix_extractor is None:
                return None
            return self.py_prefix_extractor.get_ob()

        def __set__(self, value):
            self.py_prefix_extractor = PySliceTransform(value)
            self.copts.prefix_extractor = self.py_prefix_extractor.get_transformer()


cdef class Options(ColumnFamilyOptions):
    # pxd defines:
    # cdef options.Options* opts
    # cdef PyCache py_row_cache

    def __cinit__(self):
        # Destroy the existing ColumnFamilyOptions()
        del self.copts
        self.opts = NULL
        self.copts = self.opts = new options.Options()
        self.in_use = False

    def __dealloc__(self):
        if not self.opts == NULL:
            self.copts = NULL
            del self.opts

    def __init__(self, **kwargs):
        ColumnFamilyOptions.__init__(self)
        self.py_row_cache = None

        for key, value in kwargs.items():
            setattr(self, key, value)

    property create_if_missing:
        def __get__(self):
            return self.opts.create_if_missing
        def __set__(self, value):
            self.opts.create_if_missing = value

    property error_if_exists:
        def __get__(self):
            return self.opts.error_if_exists
        def __set__(self, value):
            self.opts.error_if_exists = value

    property paranoid_checks:
        def __get__(self):
            return self.opts.paranoid_checks
        def __set__(self, value):
            self.opts.paranoid_checks = value

    property max_open_files:
        def __get__(self):
            return self.opts.max_open_files
        def __set__(self, value):
            self.opts.max_open_files = value

    property use_fsync:
        def __get__(self):
            return self.opts.use_fsync
        def __set__(self, value):
            self.opts.use_fsync = value

    property db_log_dir:
        def __get__(self):
            return string_to_path(self.opts.db_log_dir)
        def __set__(self, value):
            self.opts.db_log_dir = path_to_string(value)

    property wal_dir:
        def __get__(self):
            return string_to_path(self.opts.wal_dir)
        def __set__(self, value):
            self.opts.wal_dir = path_to_string(value)

    property delete_obsolete_files_period_micros:
        def __get__(self):
            return self.opts.delete_obsolete_files_period_micros
        def __set__(self, value):
            self.opts.delete_obsolete_files_period_micros = value

    property max_background_compactions:
        def __get__(self):
            return self.opts.max_background_compactions
        def __set__(self, value):
            self.opts.max_background_compactions = value

    property max_background_flushes:
        def __get__(self):
            return self.opts.max_background_flushes
        def __set__(self, value):
            self.opts.max_background_flushes = value

    property max_log_file_size:
        def __get__(self):
            return self.opts.max_log_file_size
        def __set__(self, value):
            self.opts.max_log_file_size = value

    property db_write_buffer_size:
        def __get__(self):
            return self.opts.db_write_buffer_size
        def __set__(self, value):
            self.opts.db_write_buffer_size = value

    property log_file_time_to_roll:
        def __get__(self):
            return self.opts.log_file_time_to_roll
        def __set__(self, value):
            self.opts.log_file_time_to_roll = value

    property keep_log_file_num:
        def __get__(self):
            return self.opts.keep_log_file_num
        def __set__(self, value):
            self.opts.keep_log_file_num = value

    property max_manifest_file_size:
        def __get__(self):
            return self.opts.max_manifest_file_size
        def __set__(self, value):
            self.opts.max_manifest_file_size = value

    property table_cache_numshardbits:
        def __get__(self):
            return self.opts.table_cache_numshardbits
        def __set__(self, value):
            self.opts.table_cache_numshardbits = value

    property wal_ttl_seconds:
        def __get__(self):
            return self.opts.WAL_ttl_seconds
        def __set__(self, value):
            self.opts.WAL_ttl_seconds = value

    property wal_size_limit_mb:
        def __get__(self):
            return self.opts.WAL_size_limit_MB
        def __set__(self, value):
            self.opts.WAL_size_limit_MB = value

    property manifest_preallocation_size:
        def __get__(self):
            return self.opts.manifest_preallocation_size
        def __set__(self, value):
            self.opts.manifest_preallocation_size = value

    property enable_write_thread_adaptive_yield:
        def __get__(self):
            return self.opts.enable_write_thread_adaptive_yield
        def __set__(self, value):
            self.opts.enable_write_thread_adaptive_yield = value

    property allow_concurrent_memtable_write:
        def __get__(self):
            return self.opts.allow_concurrent_memtable_write
        def __set__(self, value):
            self.opts.allow_concurrent_memtable_write = value

    property allow_mmap_reads:
        def __get__(self):
            return self.opts.allow_mmap_reads
        def __set__(self, value):
            self.opts.allow_mmap_reads = value

    property allow_mmap_writes:
        def __get__(self):
            return self.opts.allow_mmap_writes
        def __set__(self, value):
            self.opts.allow_mmap_writes = value

    property is_fd_close_on_exec:
        def __get__(self):
            return self.opts.is_fd_close_on_exec
        def __set__(self, value):
            self.opts.is_fd_close_on_exec = value

    property stats_dump_period_sec:
        def __get__(self):
            return self.opts.stats_dump_period_sec
        def __set__(self, value):
            self.opts.stats_dump_period_sec = value

    property advise_random_on_open:
        def __get__(self):
            return self.opts.advise_random_on_open
        def __set__(self, value):
            self.opts.advise_random_on_open = value

  # TODO: need to remove -Wconversion to make this work
  # property access_hint_on_compaction_start:
  #     def __get__(self):
  #         return self.opts.access_hint_on_compaction_start
  #     def __set__(self, AccessHint value):
  #         self.opts.access_hint_on_compaction_start = value

    property use_adaptive_mutex:
        def __get__(self):
            return self.opts.use_adaptive_mutex
        def __set__(self, value):
            self.opts.use_adaptive_mutex = value

    property bytes_per_sync:
        def __get__(self):
            return self.opts.bytes_per_sync
        def __set__(self, value):
            self.opts.bytes_per_sync = value

    property row_cache:
        def __get__(self):
            return self.py_row_cache

        def __set__(self, value):
            if value is None:
                self.py_row_cache = None
                self.opts.row_cache.reset()
            elif not isinstance(value, PyCache):
                raise Exception("row_cache must be a Cache object")
            else:
                self.py_row_cache = value
                self.opts.row_cache = self.py_row_cache.get_cache()


    # cpp_bool skip_checking_sst_file_sizes_on_db_open
    property skip_checking_sst_file_sizes_on_db_open:
        def __get__(self):
            return self.opts.skip_checking_sst_file_sizes_on_db_open
        def __set__(self, value):
            self.opts.skip_checking_sst_file_sizes_on_db_open = value

    # cpp_bool skip_stats_update_on_db_open
    property skip_stats_update_on_db_open:
        def __get__(self):
            return self.opts.skip_stats_update_on_db_open
        def __set__(self, value):
            self.opts.skip_stats_update_on_db_open = value



# TODO inherit from writableDB
cdef class WriteBatch(object):
    # pxd defines:
    # cdef db.WriteBatch* batch

    def __cinit__(self, data=None):
        self.batch = NULL
        if data is not None:
            self.batch = new db.WriteBatch(bytes_to_string(data))
        else:
            self.batch = new db.WriteBatch()

    def __dealloc__(self):
        if not self.batch == NULL:
            del self.batch

    cpdef void put(self, bytes key, bytes value, ColumnFamilyHandle column_family = None):
        cdef db.ColumnFamilyHandle* cf_handle = NULL
        if column_family is not None:
            cf_handle = column_family.get_handle()
        # nullptr is default family
        self.batch.Put(cf_handle, bytes_to_slice(key), bytes_to_slice(value))

    cpdef void merge(self, bytes key, bytes value, ColumnFamilyHandle column_family = None):
        cdef db.ColumnFamilyHandle* cf_handle = NULL
        if column_family is not None:
            cf_handle = column_family.get_handle()
        # nullptr is default family
        self.batch.Merge(cf_handle, bytes_to_slice(key), bytes_to_slice(value))

    # Here delete is with def for backwards compatibility.
    # Cython has a bug that doesn't allow a method with name `delete`
    # so we have to use a different name for `cpdef`-ed ones.
    def delete(self, bytes key, ColumnFamilyHandle column_family = None):
        return self.delete_single(key, column_family)

    cpdef void delete_single(self, bytes key, ColumnFamilyHandle column_family = None):
        cdef db.ColumnFamilyHandle* cf_handle = NULL
        if column_family is not None:
            cf_handle = column_family.get_handle()
        # nullptr is default family
        self.batch.Delete(cf_handle, bytes_to_slice(key))

    cpdef void delete_range(self, bytes begin_key, bytes end_key, ColumnFamilyHandle column_family = None):
        cdef db.ColumnFamilyHandle* cf_handle = NULL
        if column_family is not None:
            cf_handle = column_family.get_handle()

        # nullptr is default family
        self.batch.DeleteRange(cf_handle, bytes_to_slice(begin_key), bytes_to_slice(end_key))

    cpdef void clear(self):
        self.batch.Clear()

    cpdef data(self):
        return string_to_bytes(self.batch.Data())

    cpdef int count(self):
        return self.batch.Count()

    def __iter__(self):
        return WriteBatchIterator(self)


cdef class WriteBatchIterator(object):
    # Need a reference to the WriteBatch.
    # The BatchItems are only pointers to the memory in WriteBatch.

    # pxd defines:
    # cdef WriteBatch batch
    # cdef vector[db.BatchItem] items
    # cdef size_t pos

    def __init__(self, WriteBatch batch):
        cdef Status st

        self.batch = batch
        self.pos = 0

        st = db.get_batch_items(batch.batch, cython.address(self.items))
        check_status(st)

    def __iter__(self):
        return self

    def __next__(self):
        if self.pos == self.items.size():
            raise StopIteration()

        cdef str op

        if self.items[self.pos].op == db.BatchItemOpPut:
            op = "Put"
        elif self.items[self.pos].op == db.BatchItemOpMerge:
            op = "Merge"
        elif self.items[self.pos].op == db.BatchItemOpDelte:
            op = "Delete"

        if self.items[self.pos].column_family_id != 0:  # Column Family is set
            ret = (
                op,
                (
                    self.items[self.pos].column_family_id,
                    slice_to_bytes(self.items[self.pos].key)
                ),
                slice_to_bytes(self.items[self.pos].value)
            )
        else:
            ret = (
                op,
                slice_to_bytes(self.items[self.pos].key),
                slice_to_bytes(self.items[self.pos].value)
            )
        self.pos += 1
        return ret


# TODO add writableDB, ReadablewritableDB
# TODO add WriteBatch iniherited from writableDB


cdef class IDB(object):
    # Cython requires to implement methods in the class definition
    # even for abstract classes.

    # TODO move write option arguments to a separate class
    cpdef void put(self, bytes key, bytes value, cpp_bool sync = False, cpp_bool disable_wal = False, ColumnFamilyHandle column_family = None):
        pass
    cpdef void delete_single(self, bytes key, cpp_bool sync = False, cpp_bool disable_wal = False, ColumnFamilyHandle column_family = None):
        pass
    cpdef void delete_range(self, bytes begin_key, bytes end_key, cpp_bool sync = False, cpp_bool disable_wal = False, ColumnFamilyHandle column_family = None):
        pass
    cpdef void flush(self):
        pass
    cpdef void flush_wal(self, cpp_bool sync = False):
        pass
    cpdef void merge(self, bytes key, bytes value, cpp_bool sync = False, cpp_bool disable_wal = False, ColumnFamilyHandle column_family = None):
        pass
    cpdef void write(self, WriteBatch batch, cpp_bool sync = False, cpp_bool disable_wal = False):
        pass
    cpdef get(self, bytes key, ColumnFamilyHandle column_family = None):
        pass
    cpdef multi_get(self, keys):
        pass
    cpdef key_may_exist(self, bytes key, cpp_bool fetch = False, ColumnFamilyHandle column_family = None):
        pass
    cpdef Iterator iterkeys(self, ColumnFamilyHandle column_family = None):
        pass
    cpdef Iterator itervalues(self, ColumnFamilyHandle column_family = None):
        pass
    cpdef Iterator iteritems(self, ColumnFamilyHandle column_family = None):
        pass


@cython.no_gc_clear
cdef class DB(IDB):
    # pxd defines:
    # cdef Options opts
    # cdef db.DB* db
    # cdef list cf_handles
    # cdef list cf_options

    def __cinit__(self, db_name, Options opts, dict column_families=None, read_only=False):
        cdef Status st
        cdef string db_path
        cdef vector[db.ColumnFamilyDescriptor] column_family_descriptors
        cdef vector[db.ColumnFamilyHandle*] column_family_handles
        cdef bytes default_cf_name = db.kDefaultColumnFamilyName
        self.db = NULL
        self.opts = None
        self.cf_handles = []
        self.cf_options = []

        if opts.in_use:
            raise Exception("Options object is already used by another DB")

        db_path = path_to_string(db_name)
        if not column_families or default_cf_name not in column_families:
            # Always add the default column family
            column_family_descriptors.push_back(
                db.ColumnFamilyDescriptor(
                    db.kDefaultColumnFamilyName,
                    options.ColumnFamilyOptions(deref(opts.opts))
                )
            )
            self.cf_options.append(None)  # Since they are the same as db
        if column_families:
            for cf_name, cf_options in column_families.items():
                if not isinstance(cf_name, bytes):
                    raise TypeError(
                        f"column family name {cf_name!r} is not of type {bytes}!"
                    )
                if not isinstance(cf_options, ColumnFamilyOptions):
                    raise TypeError(
                        f"column family options {cf_options!r} is not of type "
                        f"{ColumnFamilyOptions}!"
                    )
                if (<ColumnFamilyOptions>cf_options).in_use:
                    raise Exception(
                        f"ColumnFamilyOptions object for {cf_name} is already "
                        "used by another Column Family"
                    )
                (<ColumnFamilyOptions>cf_options).in_use = True
                column_family_descriptors.push_back(
                    db.ColumnFamilyDescriptor(
                        cf_name,
                        deref((<ColumnFamilyOptions>cf_options).copts)
                    )
                )
                self.cf_options.append(cf_options)
        if read_only:
            with nogil:
                st = db.DB_OpenForReadOnly_ColumnFamilies(
                    deref(opts.opts),
                    db_path,
                    column_family_descriptors,
                    &column_family_handles,
                    &self.db,
                    False)
        else:
            with nogil:
                st = db.DB_Open_ColumnFamilies(
                    deref(opts.opts),
                    db_path,
                    column_family_descriptors,
                    &column_family_handles,
                    &self.db)
        check_status(st)

        for handle in column_family_handles:
            wrapper = _ColumnFamilyHandle.from_handle_ptr(handle)
            self.cf_handles.append(wrapper)

        # Inject the loggers into the python callbacks
        cdef shared_ptr[logger.Logger] info_log = self.db.GetOptions(
            self.db.DefaultColumnFamily()).info_log
        if opts.py_comparator is not None:
            opts.py_comparator.set_info_log(info_log)

        if opts.py_table_factory is not None:
            opts.py_table_factory.set_info_log(info_log)

        if opts.prefix_extractor is not None:
            opts.py_prefix_extractor.set_info_log(info_log)

        cdef ColumnFamilyOptions copts
        for idx, copts in enumerate(self.cf_options):
            if not copts:
                continue

            info_log = self.db.GetOptions(column_family_handles[idx]).info_log

            if copts.py_comparator is not None:
                copts.py_comparator.set_info_log(info_log)

            if copts.py_table_factory is not None:
                copts.py_table_factory.set_info_log(info_log)

            if copts.prefix_extractor is not None:
                copts.py_prefix_extractor.set_info_log(info_log)

        self.opts = opts
        self.opts.in_use = True

    def __dealloc__(self):
        self.close()

    cpdef void close(self):
        cdef ColumnFamilyOptions copts
        if self.db != NULL:
            # We have to make sure we delete the handles so rocksdb doesn't
            # assert when we delete the db
            self.cf_handles.clear()
            for copts in self.cf_options:
                if copts:
                    copts.in_use = False
            self.cf_options.clear()

            with nogil:
                del self.db

        if self.opts is not None:
            self.opts.in_use = False

    @property
    def column_families(self):
        return [handle.weakref for handle in self.cf_handles]

    cpdef get_column_family(self, bytes name):
        for handle in self.cf_handles:
            if handle.name == name:
                return handle.weakref

    cpdef void put(self, bytes key, bytes value, cpp_bool sync = False, cpp_bool disable_wal = False, ColumnFamilyHandle column_family = None):
        cdef Status st
        cdef options.WriteOptions opts
        opts.sync = sync
        opts.disableWAL = disable_wal

        cdef Slice c_key = bytes_to_slice(key)
        cdef Slice c_value = bytes_to_slice(value)
        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()

        if column_family is not None:
            cf_handle = column_family.get_handle()

        with nogil:
            st = self.db.Put(opts, cf_handle, c_key, c_value)
        check_status(st)

    def delete(self, bytes key, cpp_bool sync = False, cpp_bool disable_wal = False, ColumnFamilyHandle column_family = None):
        self.delete_single(key, sync=sync, disable_wal=disable_wal, column_family=column_family)

    cpdef void delete_single(self, bytes key, cpp_bool sync = False, cpp_bool disable_wal = False, ColumnFamilyHandle column_family = None):
        cdef Status st
        cdef options.WriteOptions opts
        opts.sync = sync
        opts.disableWAL = disable_wal

        cdef Slice c_key = bytes_to_slice(key)
        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()

        if column_family is not None:
            cf_handle = column_family.get_handle()

        with nogil:
            st = self.db.Delete(opts, cf_handle, c_key)
        check_status(st)

    cpdef void delete_range(self, bytes begin_key, bytes end_key, cpp_bool sync = False, cpp_bool disable_wal = False, ColumnFamilyHandle column_family = None):
        cdef Status st
        cdef options.WriteOptions opts
        opts.sync = sync
        opts.disableWAL = disable_wal

        cdef Slice c_begin_key = bytes_to_slice(begin_key)
        cdef Slice c_end_key = bytes_to_slice(end_key)

        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()
        if column_family is not None:
            cf_handle = column_family.get_handle()

        with nogil:
            st = self.db.DeleteRange(opts, cf_handle, c_begin_key, c_end_key)
        check_status(st)

    cpdef void flush(self):
        cdef Status st
        cdef FlushOptions options
        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()

        with nogil:
            st = self.db.Flush(options, cf_handle)
        check_status(st)

    cpdef void flush_wal(self, cpp_bool sync = False):
        cdef Status st
        cdef cpp_bool c_sync = sync
        with nogil:
            st = self.db.FlushWAL(c_sync)
        check_status(st)

    cpdef void merge(self, bytes key, bytes value, cpp_bool sync = False, cpp_bool disable_wal = False, ColumnFamilyHandle column_family = None):
        cdef Status st
        cdef options.WriteOptions opts
        opts.sync = sync
        opts.disableWAL = disable_wal

        cdef Slice c_key = bytes_to_slice(key)
        cdef Slice c_value = bytes_to_slice(value)
        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()
        if column_family is not None:
            cf_handle = column_family.get_handle()

        with nogil:
            st = self.db.Merge(opts, cf_handle, c_key, c_value)
        check_status(st)

    cpdef void write(self, WriteBatch batch, cpp_bool sync = False, cpp_bool disable_wal = False):
        cdef Status st
        cdef options.WriteOptions opts
        opts.sync = sync
        opts.disableWAL = disable_wal

        with nogil:
            st = self.db.Write(opts, batch.batch)
        check_status(st)

    cpdef get(self, bytes key, ColumnFamilyHandle column_family = None):
        cdef string res
        cdef Status st
        cdef options.ReadOptions opts

        cdef Slice c_key = bytes_to_slice(key)
        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()
        if column_family is not None:
            cf_handle = column_family.get_handle()

        with nogil:
            st = self.db.Get(opts, cf_handle, c_key, cython.address(res))

        if st.ok():
            return string_to_bytes(res)
        elif st.IsNotFound():
            return None
        else:
            check_status(st)

    cpdef multi_get(self, keys):
        cdef vector[string] values
        values.resize(len(keys))

        cdef db.ColumnFamilyHandle* cf_handle
        cdef vector[db.ColumnFamilyHandle*] cf_handles
        cdef vector[Slice] c_keys
        for key in keys:
            if isinstance(key, tuple):
                py_handle, key = key
                cf_handle = (<ColumnFamilyHandle?>py_handle).get_handle()
            else:
                cf_handle = self.db.DefaultColumnFamily()
            c_keys.push_back(bytes_to_slice(key))
            cf_handles.push_back(cf_handle)

        cdef options.ReadOptions opts

        cdef vector[Status] res
        with nogil:
            res = self.db.MultiGet(
                opts,
                cf_handles,
                c_keys,
                cython.address(values))

        cdef dict ret_dict = {}
        for index in range(len(keys)):
            if res[index].ok():
                ret_dict[keys[index]] = string_to_bytes(values[index])
            elif res[index].IsNotFound():
                ret_dict[keys[index]] = None
            else:
                check_status(res[index])

        return ret_dict

    cpdef key_may_exist(self, bytes key, cpp_bool fetch = False, ColumnFamilyHandle column_family = None):
        cdef string value
        cdef cpp_bool value_found
        cdef cpp_bool exists
        cdef options.ReadOptions opts
        cdef Slice c_key
        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()

        if column_family is not None:
            cf_handle = column_family.get_handle()

        c_key = bytes_to_slice(key)
        exists = False

        if fetch:
            value_found = False
            with nogil:
                exists = self.db.KeyMayExist(
                    opts,
                    cf_handle,
                    c_key,
                    cython.address(value),
                    cython.address(value_found))

            if exists:
                if value_found:
                    return (True, string_to_bytes(value))
                else:
                    return (True, None)
            else:
                return (False, None)
        else:
            with nogil:
                exists = self.db.KeyMayExist(
                    opts,
                    cf_handle,
                    c_key,
                    cython.address(value))

            return (exists, None)

    cpdef Iterator iterkeys(self, ColumnFamilyHandle column_family = None):
        cdef options.ReadOptions opts
        cdef KeysIterator it
        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()
        if column_family is not None:
            cf_handle = column_family.get_handle()

        it = KeysIterator(self)

        with nogil:
            it.ptr = self.db.NewIterator(opts, cf_handle)
        return it

    cpdef Iterator itervalues(self, ColumnFamilyHandle column_family = None):
        cdef options.ReadOptions opts
        cdef ValuesIterator it
        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()
        if column_family is not None:
            cf_handle = column_family.get_handle()

        it = ValuesIterator(self)

        with nogil:
            it.ptr = self.db.NewIterator(opts, cf_handle)
        return it

    cpdef Iterator iteritems(self, ColumnFamilyHandle column_family = None):
        cdef options.ReadOptions opts
        cdef ItemsIterator it
        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()
        if column_family is not None:
            cf_handle = column_family.get_handle()

        it = ItemsIterator.__new__(ItemsIterator)
        it.db = self

        with nogil:
            it.ptr = self.db.NewIterator(opts, cf_handle)
        return it

    cpdef iterskeys(self, column_families):
        cdef vector[db.Iterator*] iters
        iters.resize(len(column_families))
        cdef options.ReadOptions opts
        cdef db.Iterator* it_ptr
        cdef KeysIterator it
        cdef db.ColumnFamilyHandle* cf_handle
        cdef vector[db.ColumnFamilyHandle*] cf_handles

        for column_family in column_families:
            cf_handle = (<ColumnFamilyHandle?>column_family).get_handle()
            cf_handles.push_back(cf_handle)

        with nogil:
            self.db.NewIterators(opts, cf_handles, &iters)

        cf_iter = iter(column_families)
        cdef list ret = []
        for it_ptr in iters:
            it = KeysIterator(self, next(cf_iter))
            it.ptr = it_ptr
            ret.append(it)
        return ret

    cpdef itersvalues(self, column_families):
        cdef vector[db.Iterator*] iters
        iters.resize(len(column_families))
        cdef options.ReadOptions opts
        cdef db.Iterator* it_ptr
        cdef ValuesIterator it
        cdef db.ColumnFamilyHandle* cf_handle
        cdef vector[db.ColumnFamilyHandle*] cf_handles

        for column_family in column_families:
            cf_handle = (<ColumnFamilyHandle?>column_family).get_handle()
            cf_handles.push_back(cf_handle)

        with nogil:
            self.db.NewIterators(opts, cf_handles, &iters)

        cdef list ret = []
        for it_ptr in iters:
            it = ValuesIterator(self)
            it.ptr = it_ptr
            ret.append(it)
        return ret

    cpdef itersitems(self, column_families):
        cdef vector[db.Iterator*] iters
        iters.resize(len(column_families))
        cdef options.ReadOptions opts
        cdef db.Iterator* it_ptr
        cdef ItemsIterator it
        cdef db.ColumnFamilyHandle* cf_handle
        cdef vector[db.ColumnFamilyHandle*] cf_handles

        for column_family in column_families:
            cf_handle = (<ColumnFamilyHandle?>column_family).get_handle()
            cf_handles.push_back(cf_handle)

        with nogil:
            self.db.NewIterators(opts, cf_handles, &iters)


        cf_iter = iter(column_families)
        cdef list ret = []
        for it_ptr in iters:
            it = ItemsIterator(self, next(cf_iter))
            it.ptr = it_ptr
            ret.append(it)
        return ret

    cpdef snapshot(self):
        return Snapshot(self)

    cpdef get_property(self, prop, ColumnFamilyHandle column_family = None):
        cdef string value
        cdef Slice c_prop = bytes_to_slice(prop)
        cdef cpp_bool ret = False
        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()
        if column_family:
            cf_handle = column_family.get_handle()

        with nogil:
            ret = self.db.GetProperty(cf_handle, c_prop, cython.address(value))

        if ret:
            return string_to_bytes(value)
        else:
            return None

    cpdef get_live_files_metadata(self):
        cdef vector[db.LiveFileMetaData] metadata

        with nogil:
            self.db.GetLiveFilesMetaData(cython.address(metadata))

        ret = []
        for ob in metadata:
            t = {}
            t['name'] = string_to_path(ob.name)
            t['level'] = ob.level
            t['size'] = ob.size
            t['smallestkey'] = string_to_bytes(ob.smallestkey)
            t['largestkey'] = string_to_bytes(ob.largestkey)
            t['smallest_seqno'] = ob.smallest_seqno
            t['largest_seqno'] = ob.largest_seqno

            ret.append(t)

        return ret

    # TODO replace arguments with a single CompactRangeOptions cython wrapper
    cpdef void compact_range(self,
        bytes begin=None,
        bytes end=None,
        cpp_bool change_level = False,
        int target_level = -1,
        str bottommost_level_compaction = 'if_compaction_filter',
        ColumnFamilyHandle column_family = None
    ):
        cdef options.CompactRangeOptions c_options

        c_options.change_level = change_level
        c_options.target_level = target_level

        blc = bottommost_level_compaction
        if blc == 'skip':
            c_options.bottommost_level_compaction = options.blc_skip
        elif blc == 'if_compaction_filter':
            c_options.bottommost_level_compaction = options.blc_is_filter
        elif blc == 'force':
            c_options.bottommost_level_compaction = options.blc_force
        else:
            raise ValueError("bottommost_level_compaction is not valid")

        cdef Status st
        cdef Slice begin_val
        cdef Slice end_val

        cdef Slice* begin_ptr
        cdef Slice* end_ptr

        begin_ptr = NULL
        end_ptr = NULL

        if begin is not None:
            begin_val = bytes_to_slice(begin)
            begin_ptr = cython.address(begin_val)

        if end is not None:
            end_val = bytes_to_slice(end)
            end_ptr = cython.address(end_val)

        cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()
        if column_family is not None:
            cf_handle = column_family.get_handle()

        st = self.db.CompactRange(c_options, cf_handle, begin_ptr, end_ptr)
        check_status(st)

    @staticmethod
    def __parse_read_opts(
        verify_checksums=False,
        fill_cache=True,
        snapshot=None,
        read_tier="all"):

        # TODO: Is this really effiencet ?
        return locals()

    cdef options.ReadOptions build_read_opts(self, dict py_opts):
        cdef options.ReadOptions opts
        opts.verify_checksums = py_opts['verify_checksums']
        opts.fill_cache = py_opts['fill_cache']
        if py_opts['snapshot'] is not None:
            opts.snapshot = (<Snapshot?>(py_opts['snapshot'])).ptr

        if py_opts['read_tier'] == "all":
            opts.read_tier = options.kReadAllTier
        elif py_opts['read_tier'] == 'cache':
            opts.read_tier = options.kBlockCacheTier
        else:
            raise ValueError("Invalid read_tier")

        return opts

    property options:
        def __get__(self):
            return self.opts

    cpdef create_column_family(self, bytes name, ColumnFamilyOptions copts):
        cdef db.ColumnFamilyHandle* cf_handle
        cdef Status st
        cdef string c_name = name

        for handle in self.cf_handles:
            if handle.name == name:
                raise ValueError(f"{name} is already an existing column family")

        if copts.in_use:
            raise Exception("ColumnFamilyOptions are in_use by another column family")

        copts.in_use = True
        with nogil:
            st = self.db.CreateColumnFamily(deref(copts.copts), c_name, &cf_handle)
        check_status(st)

        handle = _ColumnFamilyHandle.from_handle_ptr(cf_handle)

        self.cf_handles.append(handle)
        self.cf_options.append(copts)
        return handle.weakref

    cpdef void drop_column_family(self, ColumnFamilyHandle weak_handle):
        cdef db.ColumnFamilyHandle* cf_handle
        cdef ColumnFamilyOptions copts
        cdef Status st

        cf_handle = weak_handle.get_handle()

        with nogil:
            st = self.db.DropColumnFamily(cf_handle)
        check_status(st)

        py_handle = weak_handle._ref()
        index = self.cf_handles.index(py_handle)
        copts = self.cf_options.pop(index)
        del self.cf_handles[index]
        del py_handle
        if copts:
            copts.in_use = False


cpdef repair_db(db_name, Options opts):
    cdef Status st
    cdef string db_path

    db_path = path_to_string(db_name)
    st = db.RepairDB(db_path, deref(opts.opts))
    check_status(st)


cpdef list_column_families(db_name, Options opts):
    cdef Status st
    cdef string db_path
    cdef vector[string] column_families

    db_path = path_to_string(db_name)
    with nogil:
        st = db.ListColumnFamilies(deref(opts.opts), db_path, &column_families)
    check_status(st)

    return column_families


@cython.no_gc_clear
cdef class Snapshot(object):
    # pxd defines:
    # cdef const snapshot.Snapshot* ptr
    # cdef DB db

    def __cinit__(self, DB db):
        self.db = db
        self.ptr = NULL
        with nogil:
            self.ptr = db.db.GetSnapshot()

    def __dealloc__(self):
        if not self.ptr == NULL:
            with nogil:
                self.db.db.ReleaseSnapshot(self.ptr)


cdef class Iterator:
    def __cinit__(self):
        self._current_value = None

    def __iter__(self):
        return self

    def __next__(self):
        item = self.next()
        if item is None:
            raise StopIteration
        return item

    # NOTE Iterator interface defines sentinel value of `None` so it can't
    # yield None values. However, one can still overwrite cpython's __next__ instead.
    cpdef object next(self):
        return None

    cpdef object get(self):
        if self._current_value is None:
            self._current_value = self.next()
        return self._current_value

    cpdef void skip(self):
        self._current_value = None


cdef class BaseIterator(Iterator):
    # pxd defines:
    # cdef iterator.Iterator* ptr
    # cdef DB db
    # cdef ColumnFamilyHandle handle

    def __cinit__(self, DB db = None, ColumnFamilyHandle handle = None):
        self.db = db
        self.ptr = NULL
        self.handle = handle

    def __dealloc__(self):
        if not self.ptr == NULL:
            del self.ptr

    cpdef object next(self):
        if not self.ptr.Valid():
            return None

        cdef object ret = self.get_ob()
        with nogil:
            self.ptr.Next()
        check_status(self.ptr.status())
        return ret

    cpdef object get(self):
        if not self.ptr.Valid():
            raise ValueError()

        cdef object ret = self.get_ob()
        return ret

    cpdef void skip(self):
        if not self.ptr.Valid():
            raise ValueError()
        with nogil:
            self.ptr.Next()
        check_status(self.ptr.status())

    def __reversed__(self):
        return ReversedIterator(self)

    cpdef void seek_to_first(self):
        with nogil:
            self.ptr.SeekToFirst()
        check_status(self.ptr.status())

    cpdef void seek_to_last(self):
        with nogil:
            self.ptr.SeekToLast()
        check_status(self.ptr.status())

    cpdef void seek(self, bytes key):
        cdef Slice c_key = bytes_to_slice(key)
        with nogil:
            self.ptr.Seek(c_key)
        check_status(self.ptr.status())

    cpdef void seek_for_prev(self, bytes key):
        cdef Slice c_key = bytes_to_slice(key)
        with nogil:
            self.ptr.SeekForPrev(c_key)
        check_status(self.ptr.status())

    cdef object get_ob(self):
        return None


cdef class KeysIterator(BaseIterator):
    cdef object get_ob(self):
        cdef Slice c_key
        with nogil:
            c_key = self.ptr.key()
        check_status(self.ptr.status())
        return slice_to_bytes(c_key)


cdef class ValuesIterator(BaseIterator):
    cdef object get_ob(self):
        cdef Slice c_value
        with nogil:
            c_value = self.ptr.value()
        check_status(self.ptr.status())
        return slice_to_bytes(c_value)


cdef class ItemsIterator(BaseIterator):
    cdef object get_ob(self):
        cdef Slice c_key
        cdef Slice c_value
        with nogil:
            c_key = self.ptr.key()
            c_value = self.ptr.value()
        check_status(self.ptr.status())
        return (slice_to_bytes(c_key), slice_to_bytes(c_value))


cdef class ReversedIterator(object):
    # pxd defines:
    # cdef BaseIterator it

    def __cinit__(self, BaseIterator it):
        self.it = it

    cpdef void seek_to_first(self):
        self.it.seek_to_first()

    cpdef void seek_to_last(self):
        self.it.seek_to_last()

    cpdef void seek(self, bytes key):
        self.it.seek(key)

    cpdef void seek_for_prev(self, bytes key):
        self.it.seek_for_prev(key)

    cpdef object get(self):
        return self.it.get()

    def __iter__(self):
        return self

    def __reversed__(self):
        return self.it

    def __next__(self):
        if not self.it.ptr.Valid():
            raise StopIteration()

        cdef object ret = self.it.get_ob()
        with nogil:
            self.it.ptr.Prev()
        check_status(self.it.ptr.status())
        return ret


cdef class BackupEngine(object):
    # pxd defines:
    # cdef backup.BackupEngine* engine

    def  __cinit__(self, backup_dir):
        cdef Status st
        cdef string c_backup_dir
        self.engine = NULL

        c_backup_dir = path_to_string(backup_dir)
        st = backup.BackupEngine_Open(
            env.Env_Default(),
            backup.BackupEngineOptions(c_backup_dir),
            cython.address(self.engine))

        check_status(st)

    def __dealloc__(self):
        if not self.engine == NULL:
            with nogil:
                del self.engine

    cpdef create_backup(self, DB db, flush_before_backup=False):
        cdef Status st
        cdef cpp_bool c_flush_before_backup

        c_flush_before_backup = flush_before_backup

        with nogil:
            st = self.engine.CreateNewBackup(db.db, c_flush_before_backup)
        check_status(st)

    cpdef restore_backup(self, backup_id, db_dir, wal_dir):
        cdef Status st
        cdef backup.BackupID c_backup_id
        cdef string c_db_dir
        cdef string c_wal_dir

        c_backup_id = backup_id
        c_db_dir = path_to_string(db_dir)
        c_wal_dir = path_to_string(wal_dir)

        with nogil:
            st = self.engine.RestoreDBFromBackup(
                c_backup_id,
                c_db_dir,
                c_wal_dir)

        check_status(st)

    cpdef restore_latest_backup(self, db_dir, wal_dir):
        cdef Status st
        cdef string c_db_dir
        cdef string c_wal_dir

        c_db_dir = path_to_string(db_dir)
        c_wal_dir = path_to_string(wal_dir)

        with nogil:
            st = self.engine.RestoreDBFromLatestBackup(c_db_dir, c_wal_dir)

        check_status(st)

    cpdef stop_backup(self):
        with nogil:
            self.engine.StopBackup()

    cpdef purge_old_backups(self, num_backups_to_keep):
        cdef Status st
        cdef uint32_t c_num_backups_to_keep

        c_num_backups_to_keep = num_backups_to_keep

        with nogil:
            st = self.engine.PurgeOldBackups(c_num_backups_to_keep)
        check_status(st)

    cpdef delete_backup(self, backup_id):
        cdef Status st
        cdef backup.BackupID c_backup_id

        c_backup_id = backup_id

        with nogil:
            st = self.engine.DeleteBackup(c_backup_id)

        check_status(st)

    cpdef get_backup_info(self):
        cdef vector[backup.BackupInfo] backup_info

        with nogil:
            self.engine.GetBackupInfo(cython.address(backup_info))

        ret = []
        for ob in backup_info:
            t = {}
            t['backup_id'] = ob.backup_id
            t['timestamp'] = ob.timestamp
            t['size'] = ob.size
            ret.append(t)

        return ret
