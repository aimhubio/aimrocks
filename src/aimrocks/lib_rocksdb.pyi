# import cython
# from libcpp.string cimport string
# from libcpp.deque cimport deque
# from libcpp.vector cimport vector
# from cpython cimport bool as py_bool
# from libcpp cimport bool as cpp_bool
# from libc.stdint cimport uint32_t
# from cython.operator cimport dereference as deref
# from cpython.bytes cimport PyBytes_AsString
# from cpython.bytes cimport PyBytes_Size
# from cpython.bytes cimport PyBytes_FromString
# from cpython.bytes cimport PyBytes_FromStringAndSize
# from cpython.unicode cimport PyUnicode_Decode

# from std_memory cimport shared_ptr
# cimport options
# cimport merge_operator
# cimport filter_policy
# cimport comparator
# cimport slice_transform
# cimport cache
# cimport logger
# cimport snapshot
# cimport db
# cimport iterator
# cimport backup
# cimport env
# cimport table_factory
# cimport memtablerep
# cimport universal_compaction

# # Enums are the only exception for direct imports
# # Their name als already unique enough
# from universal_compaction cimport kCompactionStopStyleSimilarSize
# from universal_compaction cimport kCompactionStopStyleTotalSize

# from options cimport kCompactionStyleLevel
# from options cimport kCompactionStyleUniversal
# from options cimport kCompactionStyleFIFO
# from options cimport kCompactionStyleNone

# from slice_ cimport Slice
# from status cimport Status

# import sys
# from interfaces import MergeOperator as IMergeOperator
# from interfaces import AssociativeMergeOperator as IAssociativeMergeOperator
# from interfaces import FilterPolicy as IFilterPolicy
# from interfaces import Comparator as IComparator
# from interfaces import SliceTransform as ISliceTransform
# import traceback
# import errors
# import weakref

# ctypedef const filter_policy.FilterPolicy ConstFilterPolicy

# cdef extern from "cpp/utils.hpp" namespace "py_rocks":
#     cdef const Slice* vector_data(vector[Slice]&)

# # Prepare python for threaded usage.
# # Python callbacks (merge, comparator)
# # could be executed in a rocksdb background thread (eg. compaction).
# cdef extern from "Python.h":
#     void PyEval_InitThreads()
# PyEval_InitThreads()

# ## Here comes the stuff to wrap the status to exception
# cdef check_status(const Status& st):
#     if st.ok():
#         return

#     if st.IsNotFound():
#         raise errors.NotFound(st.ToString())

#     if st.IsCorruption():
#         raise errors.Corruption(st.ToString())

#     if st.IsNotSupported():
#         raise errors.NotSupported(st.ToString())

#     if st.IsInvalidArgument():
#         raise errors.InvalidArgument(st.ToString())

#     if st.IsIOError():
#         raise errors.RocksIOError(st.ToString())

#     if st.IsMergeInProgress():
#         raise errors.MergeInProgress(st.ToString())

#     if st.IsIncomplete():
#         raise errors.Incomplete(st.ToString())

#     raise Exception("Unknown error: %s" % st.ToString())
# ######################################################


# cdef string bytes_to_string(path) except *:
#     return string(PyBytes_AsString(path), PyBytes_Size(path))

# cdef string_to_bytes(string ob):
#     return PyBytes_FromStringAndSize(ob.c_str(), ob.size())

# cdef Slice bytes_to_slice(ob) except *:
#     return Slice(PyBytes_AsString(ob), PyBytes_Size(ob))

# cdef slice_to_bytes(Slice sl):
#     return PyBytes_FromStringAndSize(sl.data(), sl.size())

# ## only for filsystem paths
# cdef string path_to_string(object path) except *:
#     if isinstance(path, bytes):
#         return bytes_to_string(path)
#     if isinstance(path, unicode):
#         path = path.encode(sys.getfilesystemencoding())
#         return bytes_to_string(path)
#     else:
#        raise TypeError("Wrong type for path: %s" % path)

# cdef object string_to_path(string path):
#     fs_encoding = sys.getfilesystemencoding().encode('ascii')
#     return PyUnicode_Decode(path.c_str(), path.size(), fs_encoding, "replace")

# ## Here comes the stuff for the comparator
# @cython.internal
# cdef class PyComparator(object):
#     cdef object get_ob(self):
#         return None

#     cdef const comparator.Comparator* get_comparator(self):
#         return NULL

#     cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
#         pass

# @cython.internal
# cdef class PyGenericComparator(PyComparator):
#     cdef comparator.ComparatorWrapper* comparator_ptr
#     cdef object ob

#     def __cinit__(self, object ob):
#         self.comparator_ptr = NULL
#         if not isinstance(ob, IComparator):
#             raise TypeError("%s is not of type %s" % (ob, IComparator))

#         self.ob = ob
#         self.comparator_ptr = new comparator.ComparatorWrapper(
#                 bytes_to_string(ob.name()),
#                 <void*>ob,
#                 compare_callback)

#     def __dealloc__(self):
#         if not self.comparator_ptr == NULL:
#             del self.comparator_ptr

#     cdef object get_ob(self):
#         return self.ob

#     cdef const comparator.Comparator* get_comparator(self):
#         return <comparator.Comparator*> self.comparator_ptr

#     cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
#         self.comparator_ptr.set_info_log(info_log)

# @cython.internal
# cdef class PyBytewiseComparator(PyComparator):
#     cdef const comparator.Comparator* comparator_ptr

#     def __cinit__(self):
#         self.comparator_ptr = comparator.BytewiseComparator()

#     def name(self):
#         return PyBytes_FromString(self.comparator_ptr.Name())

#     def compare(self, a, b):
#         return self.comparator_ptr.Compare(
#             bytes_to_slice(a),
#             bytes_to_slice(b))

#     cdef object get_ob(self):
#        return self

#     cdef const comparator.Comparator* get_comparator(self):
#         return self.comparator_ptr



# cdef int compare_callback(
#     void* ctx,
#     logger.Logger* log,
#     string& error_msg,
#     const Slice& a,
#     const Slice& b) with gil:

#     try:
#         return (<object>ctx).compare(slice_to_bytes(a), slice_to_bytes(b))
#     except BaseException as error:
#         tb = traceback.format_exc()
#         logger.Log(log, "Error in compare callback: %s", <bytes>tb)
#         error_msg.assign(<bytes>str(error))

# BytewiseComparator = PyBytewiseComparator
# #########################################



# ## Here comes the stuff for the filter policy
# @cython.internal
# cdef class PyFilterPolicy(object):
#     cdef object get_ob(self):
#         return None

#     cdef shared_ptr[ConstFilterPolicy] get_policy(self):
#         return shared_ptr[ConstFilterPolicy]()

#     cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
#         pass

# @cython.internal
# cdef class PyGenericFilterPolicy(PyFilterPolicy):
#     cdef shared_ptr[filter_policy.FilterPolicyWrapper] policy
#     cdef object ob

#     def __cinit__(self, object ob):
#         if not isinstance(ob, IFilterPolicy):
#             raise TypeError("%s is not of type %s" % (ob, IFilterPolicy))

#         self.ob = ob
#         self.policy.reset(new filter_policy.FilterPolicyWrapper(
#                 bytes_to_string(ob.name()),
#                 <void*>ob,
#                 create_filter_callback,
#                 key_may_match_callback))

#     cdef object get_ob(self):
#         return self.ob

#     cdef shared_ptr[ConstFilterPolicy] get_policy(self):
#         return <shared_ptr[ConstFilterPolicy]>(self.policy)

#     cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
#         self.policy.get().set_info_log(info_log)


# cdef void create_filter_callback(
#     void* ctx,
#     logger.Logger* log,
#     string& error_msg,
#     const Slice* keys,
#     int n,
#     string* dst) with gil:

#     try:
#         ret = (<object>ctx).create_filter(
#             [slice_to_bytes(keys[i]) for i in range(n)])
#         dst.append(bytes_to_string(ret))
#     except BaseException as error:
#         tb = traceback.format_exc()
#         logger.Log(log, "Error in create filter callback: %s", <bytes>tb)
#         error_msg.assign(<bytes>str(error))

# cdef cpp_bool key_may_match_callback(
#     void* ctx,
#     logger.Logger* log,
#     string& error_msg,
#     const Slice& key,
#     const Slice& filt) with gil:

#     try:
#         return (<object>ctx).key_may_match(
#             slice_to_bytes(key),
#             slice_to_bytes(filt))
#     except BaseException as error:
#         tb = traceback.format_exc()
#         logger.Log(log, "Error in key_mach_match callback: %s", <bytes>tb)
#         error_msg.assign(<bytes>str(error))

# @cython.internal
# cdef class PyBloomFilterPolicy(PyFilterPolicy):
#     cdef shared_ptr[ConstFilterPolicy] policy

#     def __cinit__(self, int bits_per_key):
#         self.policy.reset(filter_policy.NewBloomFilterPolicy(bits_per_key))

#     def name(self):
#         return PyBytes_FromString(self.policy.get().Name())

#     def create_filter(self, keys):
#         cdef string dst
#         cdef vector[Slice] c_keys

#         for key in keys:
#             c_keys.push_back(bytes_to_slice(key))

#         self.policy.get().CreateFilter(
#             vector_data(c_keys),
#             <int>c_keys.size(),
#             cython.address(dst))

#         return string_to_bytes(dst)

#     def key_may_match(self, key, filter_):
#         return self.policy.get().KeyMayMatch(
#             bytes_to_slice(key),
#             bytes_to_slice(filter_))

#     cdef object get_ob(self):
#         return self

#     cdef shared_ptr[ConstFilterPolicy] get_policy(self):
#         return self.policy

# BloomFilterPolicy = PyBloomFilterPolicy
# #############################################



# ## Here comes the stuff for the merge operator
# @cython.internal
# cdef class PyMergeOperator(object):
#     cdef shared_ptr[merge_operator.MergeOperator] merge_op
#     cdef object ob

#     def __cinit__(self, object ob):
#         self.ob = ob
#         if isinstance(ob, IAssociativeMergeOperator):
#             self.merge_op.reset(
#                 <merge_operator.MergeOperator*>
#                     new merge_operator.AssociativeMergeOperatorWrapper(
#                         bytes_to_string(ob.name()),
#                         <void*>(ob),
#                         merge_callback))

#         elif isinstance(ob, IMergeOperator):
#             self.merge_op.reset(
#                 <merge_operator.MergeOperator*>
#                     new merge_operator.MergeOperatorWrapper(
#                         bytes_to_string(ob.name()),
#                         <void*>ob,
#                         <void*>ob,
#                         full_merge_callback,
#                         partial_merge_callback))
#         #  elif isinstance(ob, str):
#             #  if ob == "put":
#               #  self.merge_op = merge_operator.MergeOperators.CreatePutOperator()
#             #  elif ob == "put_v1":
#               #  self.merge_op = merge_operator.MergeOperators.CreateDeprecatedPutOperator()
#             #  elif ob == "uint64add":
#               #  self.merge_op = merge_operator.MergeOperators.CreateUInt64AddOperator()
#             #  elif ob == "stringappend":
#               #  self.merge_op = merge_operator.MergeOperators.CreateStringAppendOperator()
#             #  #TODO: necessary?
#             #  #  elif ob == "stringappendtest":
#               #  #  self.merge_op = merge_operator.MergeOperators.CreateStringAppendTESTOperator()
#             #  elif ob == "max":
#               #  self.merge_op = merge_operator.MergeOperators.CreateMaxOperator()
#             #  else:
#                 #  msg = "{0} is not the default type".format(ob)
#                 #  raise TypeError(msg)
#         else:
#             msg = "%s is not of this types %s"
#             msg %= (ob, (IAssociativeMergeOperator, IMergeOperator))
#             raise TypeError(msg)


#     cdef object get_ob(self):
#         return self.ob

#     cdef shared_ptr[merge_operator.MergeOperator] get_operator(self):
#         return self.merge_op

# cdef cpp_bool merge_callback(
#     void* ctx,
#     const Slice& key,
#     const Slice* existing_value,
#     const Slice& value,
#     string* new_value,
#     logger.Logger* log) with gil:

#     if existing_value == NULL:
#         py_existing_value = None
#     else:
#         py_existing_value = slice_to_bytes(deref(existing_value))

#     try:
#         ret = (<object>ctx).merge(
#             slice_to_bytes(key),
#             py_existing_value,
#             slice_to_bytes(value))

#         if ret[0]:
#             new_value.assign(bytes_to_string(ret[1]))
#             return True
#         return False

#     except:
#         tb = traceback.format_exc()
#         logger.Log(log, "Error in merge_callback: %s", <bytes>tb)
#         return False

# cdef cpp_bool full_merge_callback(
#     void* ctx,
#     const Slice& key,
#     const Slice* existing_value,
#     const deque[string]& op_list,
#     string* new_value,
#     logger.Logger* log) with gil:

#     if existing_value == NULL:
#         py_existing_value = None
#     else:
#         py_existing_value = slice_to_bytes(deref(existing_value))

#     try:
#         ret = (<object>ctx).full_merge(
#             slice_to_bytes(key),
#             py_existing_value,
#             [string_to_bytes(op_list[i]) for i in range(op_list.size())])

#         if ret[0]:
#             new_value.assign(bytes_to_string(ret[1]))
#             return True
#         return False

#     except:
#         tb = traceback.format_exc()
#         logger.Log(log, "Error in full_merge_callback: %s", <bytes>tb)
#         return False

# cdef cpp_bool partial_merge_callback(
#     void* ctx,
#     const Slice& key,
#     const Slice& left_op,
#     const Slice& right_op,
#     string* new_value,
#     logger.Logger* log) with gil:

#     try:
#         ret = (<object>ctx).partial_merge(
#             slice_to_bytes(key),
#             slice_to_bytes(left_op),
#             slice_to_bytes(right_op))

#         if ret[0]:
#             new_value.assign(bytes_to_string(ret[1]))
#             return True
#         return False

#     except:
#         tb = traceback.format_exc()
#         logger.Log(log, "Error in partial_merge_callback: %s", <bytes>tb)
#         return False
# ##############################################

# #### Here comes the Cache stuff
# @cython.internal
# cdef class PyCache(object):
#     cdef shared_ptr[cache.Cache] get_cache(self):
#         return shared_ptr[cache.Cache]()

# @cython.internal
# cdef class PyLRUCache(PyCache):
#     cdef shared_ptr[cache.Cache] cache_ob

#     def __cinit__(self, capacity, shard_bits=None):
#         if shard_bits is not None:
#             self.cache_ob = cache.NewLRUCache(capacity, shard_bits)
#         else:
#             self.cache_ob = cache.NewLRUCache(capacity)

#     cdef shared_ptr[cache.Cache] get_cache(self):
#         return self.cache_ob

# LRUCache = PyLRUCache
# ###############################

# ### Here comes the stuff for SliceTransform
# @cython.internal
# cdef class PySliceTransform(object):
#     cdef shared_ptr[slice_transform.SliceTransform] transfomer
#     cdef object ob

#     def __cinit__(self, object ob):
#         if not isinstance(ob, ISliceTransform):
#             raise TypeError("%s is not of type %s" % (ob, ISliceTransform))

#         self.ob = ob
#         self.transfomer.reset(
#             <slice_transform.SliceTransform*>
#                 new slice_transform.SliceTransformWrapper(
#                     bytes_to_string(ob.name()),
#                     <void*>ob,
#                     slice_transform_callback,
#                     slice_in_domain_callback,
#                     slice_in_range_callback))

#     cdef object get_ob(self):
#         return self.ob

#     cdef shared_ptr[slice_transform.SliceTransform] get_transformer(self):
#         return self.transfomer

#     cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
#         cdef slice_transform.SliceTransformWrapper* ptr
#         ptr = <slice_transform.SliceTransformWrapper*> self.transfomer.get()
#         ptr.set_info_log(info_log)


# cdef Slice slice_transform_callback(
#     void* ctx,
#     logger.Logger* log,
#     string& error_msg,
#     const Slice& src) with gil:

#     cdef size_t offset
#     cdef size_t size

#     try:
#         ret = (<object>ctx).transform(slice_to_bytes(src))
#         offset = ret[0]
#         size = ret[1]
#         if (offset + size) > src.size():
#             msg = "offset(%i) + size(%i) is bigger than slice(%i)"
#             raise Exception(msg  % (offset, size, src.size()))

#         return Slice(src.data() + offset, size)
#     except BaseException as error:
#         tb = traceback.format_exc()
#         logger.Log(log, "Error in slice transfrom callback: %s", <bytes>tb)
#         error_msg.assign(<bytes>str(error))

# cdef cpp_bool slice_in_domain_callback(
#     void* ctx,
#     logger.Logger* log,
#     string& error_msg,
#     const Slice& src) with gil:

#     try:
#         return (<object>ctx).in_domain(slice_to_bytes(src))
#     except BaseException as error:
#         tb = traceback.format_exc()
#         logger.Log(log, "Error in slice transfrom callback: %s", <bytes>tb)
#         error_msg.assign(<bytes>str(error))

# cdef cpp_bool slice_in_range_callback(
#     void* ctx,
#     logger.Logger* log,
#     string& error_msg,
#     const Slice& src) with gil:

#     try:
#         return (<object>ctx).in_range(slice_to_bytes(src))
#     except BaseException as error:
#         tb = traceback.format_exc()
#         logger.Log(log, "Error in slice transfrom callback: %s", <bytes>tb)
#         error_msg.assign(<bytes>str(error))
# ###########################################

# ## Here are the TableFactories
# @cython.internal
# cdef class PyTableFactory(object):
#     cdef shared_ptr[table_factory.TableFactory] factory

#     cdef shared_ptr[table_factory.TableFactory] get_table_factory(self):
#         return self.factory

#     cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
#         pass

# cdef class BlockBasedTableFactory(PyTableFactory):
#     cdef PyFilterPolicy py_filter_policy

#     def __init__(self,
#             index_type='binary_search',
#             py_bool hash_index_allow_collision=True,
#             checksum='crc32',
#             PyCache block_cache=None,
#             PyCache block_cache_compressed=None,
#             filter_policy=None,
#             no_block_cache=False,
#             block_size=None,
#             block_size_deviation=None,
#             block_restart_interval=None,
#             whole_key_filtering=None):

#         cdef table_factory.BlockBasedTableOptions table_options

#         if index_type == 'binary_search':
#             table_options.index_type = table_factory.kBinarySearch
#         elif index_type == 'hash_search':
#             table_options.index_type = table_factory.kHashSearch
#         else:
#             raise ValueError("Unknown index_type: %s" % index_type)

#         if hash_index_allow_collision:
#             table_options.hash_index_allow_collision = True
#         else:
#             table_options.hash_index_allow_collision = False

#         if checksum == 'crc32':
#             table_options.checksum = table_factory.kCRC32c
#         elif checksum == 'xxhash':
#             table_options.checksum = table_factory.kxxHash
#         else:
#             raise ValueError("Unknown checksum: %s" % checksum)

#         if no_block_cache:
#             table_options.no_block_cache = True
#         else:
#             table_options.no_block_cache = False

#         # If the following options are None use the rocksdb default.
#         if block_size is not None:
#             table_options.block_size = block_size

#         if block_size_deviation is not None:
#             table_options.block_size_deviation = block_size_deviation

#         if block_restart_interval is not None:
#             table_options.block_restart_interval = block_restart_interval

#         if whole_key_filtering is not None:
#             if whole_key_filtering:
#                 table_options.whole_key_filtering = True
#             else:
#                 table_options.whole_key_filtering = False

#         if block_cache is not None:
#             table_options.block_cache = block_cache.get_cache()

#         if block_cache_compressed is not None:
#             table_options.block_cache_compressed = block_cache_compressed.get_cache()

#         # Set the filter_policy
#         self.py_filter_policy = None
#         if filter_policy is not None:
#             if isinstance(filter_policy, PyFilterPolicy):
#                 if (<PyFilterPolicy?>filter_policy).get_policy().get() == NULL:
#                     raise Exception("Cannot set filter policy: %s" % filter_policy)
#                 self.py_filter_policy = filter_policy
#             else:
#                 self.py_filter_policy = PyGenericFilterPolicy(filter_policy)

#             table_options.filter_policy = self.py_filter_policy.get_policy()

#         self.factory.reset(table_factory.NewBlockBasedTableFactory(table_options))

#     cdef set_info_log(self, shared_ptr[logger.Logger] info_log):
#         if self.py_filter_policy is not None:
#             self.py_filter_policy.set_info_log(info_log)

# cdef class PlainTableFactory(PyTableFactory):
#     def __init__(
#             self,
#             user_key_len=0,
#             bloom_bits_per_key=10,
#             hash_table_ratio=0.75,
#             index_sparseness=10,
#             huge_page_tlb_size=0,
#             encoding_type='plain',
#             py_bool full_scan_mode=False):

#         cdef table_factory.PlainTableOptions table_options

#         table_options.user_key_len = user_key_len
#         table_options.bloom_bits_per_key = bloom_bits_per_key
#         table_options.hash_table_ratio = hash_table_ratio
#         table_options.index_sparseness = index_sparseness
#         table_options.huge_page_tlb_size = huge_page_tlb_size

#         if encoding_type == 'plain':
#             table_options.encoding_type = table_factory.kPlain
#         elif encoding_type == 'prefix':
#             table_options.encoding_type = table_factory.kPrefix
#         else:
#             raise ValueError("Unknown encoding_type: %s" % encoding_type)

#         table_options.full_scan_mode = full_scan_mode

#         self.factory.reset( table_factory.NewPlainTableFactory(table_options))
# #############################################

# ### Here are the MemtableFactories
# @cython.internal
# cdef class PyMemtableFactory(object):
#     cdef shared_ptr[memtablerep.MemTableRepFactory] factory

#     cdef shared_ptr[memtablerep.MemTableRepFactory] get_memtable_factory(self):
#         return self.factory

# cdef class SkipListMemtableFactory(PyMemtableFactory):
#     def __init__(self):
#         self.factory.reset(memtablerep.NewSkipListFactory())

# cdef class VectorMemtableFactory(PyMemtableFactory):
#     def __init__(self, count=0):
#         self.factory.reset(memtablerep.NewVectorRepFactory(count))

# cdef class HashSkipListMemtableFactory(PyMemtableFactory):
#     def __init__(
#             self,
#             bucket_count=1000000,
#             skiplist_height=4,
#             skiplist_branching_factor=4):

#         self.factory.reset(
#             memtablerep.NewHashSkipListRepFactory(
#                 bucket_count,
#                 skiplist_height,
#                 skiplist_branching_factor))

# cdef class HashLinkListMemtableFactory(PyMemtableFactory):
#     def __init__(self, bucket_count=50000):
#         self.factory.reset(memtablerep.NewHashLinkListRepFactory(bucket_count))
# ##################################


# cdef class CompressionType(object):
#     no_compression = u'no_compression'
#     snappy_compression = u'snappy_compression'
#     zlib_compression = u'zlib_compression'
#     bzip2_compression = u'bzip2_compression'
#     lz4_compression = u'lz4_compression'
#     lz4hc_compression = u'lz4hc_compression'
#     xpress_compression = u'xpress_compression'
#     zstd_compression = u'zstd_compression'
#     zstdnotfinal_compression = u'zstdnotfinal_compression'
#     disable_compression = u'disable_compression'

# cdef class CompactionPri(object):
#     by_compensated_size = u'by_compensated_size'
#     oldest_largest_seq_first = u'oldest_largest_seq_first'
#     oldest_smallest_seq_first = u'oldest_smallest_seq_first'
#     min_overlapping_ratio = u'min_overlapping_ratio'

# @cython.internal
# cdef class _ColumnFamilyHandle:
#     """ This is an internal class that we will weakref for safety """
#     cdef db.ColumnFamilyHandle* handle
#     cdef object __weakref__
#     cdef object weak_handle

#     def __cinit__(self):
#         self.handle = NULL

#     def __dealloc__(self):
#         if not self.handle == NULL:
#             del self.handle

#     @staticmethod
#     cdef from_handle_ptr(db.ColumnFamilyHandle* handle):
#         inst = <_ColumnFamilyHandle>_ColumnFamilyHandle.__new__(_ColumnFamilyHandle)
#         inst.handle = handle
#         return inst

#     @property
#     def name(self):
#         return self.handle.GetName()

#     @property
#     def id(self):
#         return self.handle.GetID()

#     @property
#     def weakref(self):
#         if self.weak_handle is None:
#             self.weak_handle = ColumnFamilyHandle.from_wrapper(self)
#         return self.weak_handle

class ColumnFamilyHandle:

    @property
    def is_valid(self) -> bool:
        ...

    def __repr__(self) -> str:
        ...

    def __eq__(self, other) -> bool:
        ...

    def __lt__(self, other) -> bool:
        ...

    def __ne__(self, other):
        return not self == other

    def __gt__(self, other):
        return other < self

    def __le__(self, other):
        return not other < self

    def __ge__(self, other):
        return not self < other

    def __hash__(self) -> int:
        ...


class ColumnFamilyOptions(object):

    def __init__(self, **kwargs):
        self.py_comparator = None
        self.py_merge_operator = None
        self.py_prefix_extractor = None
        self.py_table_factory = None
        self.py_memtable_factory = None
        self.write_buffer_size = None
        self.max_write_buffer_number = None
        self.min_write_buffer_number_to_merge = None
        self.compression_opts = None
        self.compaction_pri = None
        self.compression = None
        self.max_compaction_bytes = None
        self.num_levels = None
        self.level0_file_num_compaction_trigger = None
        self.level0_slowdown_writes_trigger = None
        self.level0_stop_writes_trigger = None
        self.max_mem_compaction_level = None
        self.target_file_size_base = None
        self.target_file_size_multiplier = None
        self.max_bytes_for_level_base = None
        self.max_bytes_for_level_multiplier = None
        self.max_bytes_for_level_multiplier_additional = None
        self.arena_block_size = None
        self.disable_auto_compactions = None
        self.compaction_style = None
        self.compaction_options_universal = None
        self.max_sequential_skip_in_iterations = None
        self.inplace_update_support = None
        self.table_factory = None
        self.memtable_factory = None
        self.inplace_update_num_locks = None
        self.comparator = None
        self.merge_operator = None
        self.prefix_extractors = None


class Options(ColumnFamilyOptions):

    def __init__(self, **kwargs):
        super().__init__()
        self.create_if_missing: bool
        self.error_if_exists: bool
        self.paranoid_checks: bool
        self.max_open_files = None
        self.use_fsync: bool
        self.db_log_dir = None
        self.wal_dir = None
        self.delete_obsolete_files_period_micros: bool
        self.max_background_compactions = None
        self.max_background_flushes = None
        self.max_log_file_size = None
        self.log_file_time_to_roll = None
        self.keep_log_file_num = None
        self.max_manifest_file_size = None
        self.table_cache_numshardbits = None
        self.wal_ttl_seconds = None
        self.wal_size_limit_mb = None
        self.manifest_preallocation_size = None
        self.enable_write_thread_adaptive_yield = None
        self.allow_concurrent_memtable_write = None
        self.allow_mmap_reads = None
        self.allow_mmap_writes = None
        self.is_fd_close_on_exec = None
        self.stats_dump_period_sec = None
        self.advise_random_on_open = None
        self.use_adaptive_mutex = None
        self.bytes_per_sync = None
        self.row_cache = None


# # Forward declaration
# cdef class Snapshot

# cdef class KeysIterator
# cdef class ValuesIterator
# cdef class ItemsIterator
# cdef class ReversedIterator

# # Forward declaration
# cdef class WriteBatchIterator

class WriteBatch(object):

    def __init__(self, data=None):
        ...

    def put(self, key: bytes, value: bytes):
        ...

    def merge(self, key: bytes, value: bytes):
        ...

    def delete(self, key: bytes):
        ...

    def delete_range(self, key: Tuple[bytes, bytes]):
        ...

    def clear(self):
        ...

    def data(self):
        ...

    def count(self):
        ...

    def __iter__(self):
        ...


# @cython.internal
# cdef class WriteBatchIterator(object):
#     # Need a reference to the WriteBatch.
#     # The BatchItems are only pointers to the memory in WriteBatch.
#     cdef WriteBatch batch
#     cdef vector[db.BatchItem] items
#     cdef size_t pos

#     def __init__(self, WriteBatch batch):
#         cdef Status st

#         self.batch = batch
#         self.pos = 0

#         st = db.get_batch_items(batch.batch, cython.address(self.items))
#         check_status(st)

#     def __iter__(self):
#         return self

#     def __next__(self):
#         if self.pos == self.items.size():
#             raise StopIteration()

#         cdef str op

#         if self.items[self.pos].op == db.BatchItemOpPut:
#             op = "Put"
#         elif self.items[self.pos].op == db.BatchItemOpMerge:
#             op = "Merge"
#         elif self.items[self.pos].op == db.BatchItemOpDelte:
#             op = "Delete"

#         if self.items[self.pos].column_family_id != 0:  # Column Family is set
#             ret = (
#                 op,
#                 (
#                     self.items[self.pos].column_family_id,
#                     slice_to_bytes(self.items[self.pos].key)
#                 ),
#                 slice_to_bytes(self.items[self.pos].value)
#             )
#         else:
#             ret = (
#                 op,
#                 slice_to_bytes(self.items[self.pos].key),
#                 slice_to_bytes(self.items[self.pos].value)
#             )
#         self.pos += 1
#         return ret


from typing import Any, Dict, Iterable, List, Tuple


class DB(object):

    def __init__(self,
                 db_name: str,
                 opts: 'Options',
                 column_families: dict = None,
                 read_only: bool = False):
        ...
        self.opts = opts
        self.opts.in_use = True

    def __dealloc__(self):
        self.close()

    def close(self):
        ...

    @property
    def column_families(self) -> list:
        ...

    def get_column_family(self, name: bytes):
        ...

    def put(
        self,
        key: bytes,
        value: bytes,
        sync: bool = False,
        disable_wal: bool = False
    ):
        ...

    def delete(
        self,
        key: bytes,
        sync: bool = False,
        disable_wal: bool = False
    ):
        ...

    def delete_range(
        self,
        key: Tuple[bytes, bytes],
        sync: bool = False,
        disable_wal: bool = False
    ):
        ...

    def merge(
        self,
        key: bytes,
        value: bytes,
        sync: bool = False,
        disable_wal: bool = False
    ):
        ...

    def write(
        self,
        batch: 'WriteBatch',
        sync: bool = False,
        disable_wal: bool = False
    ):
        ...

    def get(
        self,
        key: bytes,
        *args,
        **kwargs
    ) -> bytes:
        ...

    def multi_get(
        self,
        keys: Iterable[bytes],
        *args,
        **kwargs
    ) -> Dict[bytes, bytes]:
        ...

    def key_may_exist(
        self,
        key: bytes,
        fetch: bool = False,
        *args,
        **kwargs
    ) -> Tuple[bool, Any]:
        ...

    def iterkeys(
        self,
        column_family: 'ColumnFamilyHandle' = None,
        *args,
        **kwargs
    ) -> 'KeysIterator':
        ...

    def itervalues(
        self,
        column_family: 'ColumnFamilyHandle' = None,
        *args,
        **kwargs
    ) -> 'ValuesIterator':
        ...

    def iteritems(
        self,
        column_family: 'ColumnFamilyHandle' = None,
        *args,
        **kwargs
    ) -> 'ItemsIterator':
        ...

    # def iterskeys(self, column_families, *args, **kwargs):
    #     cdef vector[db.Iterator*] iters
    #     iters.resize(len(column_families))
    #     cdef options.ReadOptions opts
    #     cdef db.Iterator* it_ptr
    #     cdef KeysIterator it
    #     cdef db.ColumnFamilyHandle* cf_handle
    #     cdef vector[db.ColumnFamilyHandle*] cf_handles

    #     for column_family in column_families:
    #         cf_handle = (<ColumnFamilyHandle?>column_family).get_handle()
    #         cf_handles.push_back(cf_handle)

    #     opts = self.build_read_opts(self.__parse_read_opts(*args, **kwargs))
    #     with nogil:
    #         self.db.NewIterators(opts, cf_handles, &iters)

    #     cf_iter = iter(column_families)
    #     cdef list ret = []
    #     for it_ptr in iters:
    #         it = KeysIterator(self, next(cf_iter))
    #         it.ptr = it_ptr
    #         ret.append(it)
    #     return ret

    # def itersvalues(self, column_families, *args, **kwargs):
    #     cdef vector[db.Iterator*] iters
    #     iters.resize(len(column_families))
    #     cdef options.ReadOptions opts
    #     cdef db.Iterator* it_ptr
    #     cdef ValuesIterator it
    #     cdef db.ColumnFamilyHandle* cf_handle
    #     cdef vector[db.ColumnFamilyHandle*] cf_handles

    #     for column_family in column_families:
    #         cf_handle = (<ColumnFamilyHandle?>column_family).get_handle()
    #         cf_handles.push_back(cf_handle)

    #     opts = self.build_read_opts(self.__parse_read_opts(*args, **kwargs))
    #     with nogil:
    #         self.db.NewIterators(opts, cf_handles, &iters)

    #     cdef list ret = []
    #     for it_ptr in iters:
    #         it = ValuesIterator(self)
    #         it.ptr = it_ptr
    #         ret.append(it)
    #     return ret

    # def iterskeys(self, column_families, *args, **kwargs):
    #     cdef vector[db.Iterator*] iters
    #     iters.resize(len(column_families))
    #     cdef options.ReadOptions opts
    #     cdef db.Iterator* it_ptr
    #     cdef ItemsIterator it
    #     cdef db.ColumnFamilyHandle* cf_handle
    #     cdef vector[db.ColumnFamilyHandle*] cf_handles

    #     for column_family in column_families:
    #         cf_handle = (<ColumnFamilyHandle?>column_family).get_handle()
    #         cf_handles.push_back(cf_handle)

    #     opts = self.build_read_opts(self.__parse_read_opts(*args, **kwargs))
    #     with nogil:
    #         self.db.NewIterators(opts, cf_handles, &iters)


    #     cf_iter = iter(column_families)
    #     cdef list ret = []
    #     for it_ptr in iters:
    #         it = ItemsIterator(self, next(cf_iter))
    #         it.ptr = it_ptr
    #         ret.append(it)
    #     return ret

    # def snapshot(self):
    #     return Snapshot(self)

    def get_property(self, prop: bytes, column_family: 'ColumnFamilyHandle' = None):
        ...

    def get_live_files_metadata(self) -> List[Dict[str, Any]]:
        ...

    # def compact_range(self, begin=None, end=None, ColumnFamilyHandle column_family=None, **py_options):
    #     cdef options.CompactRangeOptions c_options

    #     c_options.change_level = py_options.get('change_level', False)
    #     c_options.target_level = py_options.get('target_level', -1)

    #     blc = py_options.get('bottommost_level_compaction', 'if_compaction_filter')
    #     if blc == 'skip':
    #         c_options.bottommost_level_compaction = options.blc_skip
    #     elif blc == 'if_compaction_filter':
    #         c_options.bottommost_level_compaction = options.blc_is_filter
    #     elif blc == 'force':
    #         c_options.bottommost_level_compaction = options.blc_force
    #     else:
    #         raise ValueError("bottommost_level_compaction is not valid")

    #     cdef Status st
    #     cdef Slice begin_val
    #     cdef Slice end_val

    #     cdef Slice* begin_ptr
    #     cdef Slice* end_ptr

    #     begin_ptr = NULL
    #     end_ptr = NULL

    #     if begin is not None:
    #         begin_val = bytes_to_slice(begin)
    #         begin_ptr = cython.address(begin_val)

    #     if end is not None:
    #         end_val = bytes_to_slice(end)
    #         end_ptr = cython.address(end_val)

    #     cdef db.ColumnFamilyHandle* cf_handle = self.db.DefaultColumnFamily()
    #     if column_family:
    #         cf_handle = (<ColumnFamilyHandle?>column_family).get_handle()

    #     st = self.db.CompactRange(c_options, cf_handle, begin_ptr, end_ptr)
    #     check_status(st)

    # @staticmethod
    # def __parse_read_opts(
    #     verify_checksums=False,
    #     fill_cache=True,
    #     snapshot=None,
    #     read_tier="all"):

    #     # TODO: Is this really effiencet ?
    #     return locals()

    # cdef options.ReadOptions build_read_opts(self, dict py_opts):
    #     cdef options.ReadOptions opts
    #     opts.verify_checksums = py_opts['verify_checksums']
    #     opts.fill_cache = py_opts['fill_cache']
    #     if py_opts['snapshot'] is not None:
    #         opts.snapshot = (<Snapshot?>(py_opts['snapshot'])).ptr

    #     if py_opts['read_tier'] == "all":
    #         opts.read_tier = options.kReadAllTier
    #     elif py_opts['read_tier'] == 'cache':
    #         opts.read_tier = options.kBlockCacheTier
    #     else:
    #         raise ValueError("Invalid read_tier")

    #     return opts

    # property options:
    #     def __get__(self):
    #         return self.opts

    # def create_column_family(self, bytes name, ColumnFamilyOptions copts):
    #     cdef db.ColumnFamilyHandle* cf_handle
    #     cdef Status st
    #     cdef string c_name = name

    #     for handle in self.cf_handles:
    #         if handle.name == name:
    #             raise ValueError(f"{name} is already an existing column family")

    #     if copts.in_use:
    #         raise Exception("ColumnFamilyOptions are in_use by another column family")

    #     copts.in_use = True
    #     with nogil:
    #         st = self.db.CreateColumnFamily(deref(copts.copts), c_name, &cf_handle)
    #     check_status(st)

    #     handle = _ColumnFamilyHandle.from_handle_ptr(cf_handle)

    #     self.cf_handles.append(handle)
    #     self.cf_options.append(copts)
    #     return handle.weakref

    # def drop_column_family(self, ColumnFamilyHandle weak_handle not None):
    #     cdef db.ColumnFamilyHandle* cf_handle
    #     cdef ColumnFamilyOptions copts
    #     cdef Status st

    #     cf_handle = weak_handle.get_handle()

    #     with nogil:
    #         st = self.db.DropColumnFamily(cf_handle)
    #     check_status(st)

    #     py_handle = weak_handle._ref()
    #     index = self.cf_handles.index(py_handle)
    #     copts = self.cf_options.pop(index)
    #     del self.cf_handles[index]
    #     del py_handle
    #     if copts:
    #         copts.in_use = False


# def repair_db(db_name, Options opts):
#     cdef Status st
#     cdef string db_path

#     db_path = path_to_string(db_name)
#     st = db.RepairDB(db_path, deref(opts.opts))
#     check_status(st)


# def list_column_families(db_name, Options opts):
#     cdef Status st
#     cdef string db_path
#     cdef vector[string] column_families

#     db_path = path_to_string(db_name)
#     with nogil:
#         st = db.ListColumnFamilies(deref(opts.opts), db_path, &column_families)
#     check_status(st)

#     return column_families


# @cython.no_gc_clear
# @cython.internal
# cdef class Snapshot(object):
#     cdef const snapshot.Snapshot* ptr
#     cdef DB db

#     def __cinit__(self, DB db):
#         self.db = db
#         self.ptr = NULL
#         with nogil:
#             self.ptr = db.db.GetSnapshot()

#     def __dealloc__(self):
#         if not self.ptr == NULL:
#             with nogil:
#                 self.db.db.ReleaseSnapshot(self.ptr)


class BaseIterator(object):
    def __init__(self, db: 'DB', handle: 'ColumnFamilyHandle' = None):
        ...

    def __dealloc__(self):
        ...

    def __iter__(self):
        return self

    def __next__(self):
        ...

    def get(self):
        ...

    def __reversed__(self):
        ...

    def seek_to_first(self):
        ...

    def seek_to_last(self):
        ...

    def seek(self, key: bytes):
        ...

    def seek_for_prev(self, key):
        ...

    def get_ob(self):
        return None


class KeysIterator(BaseIterator):
    def get(self) -> bytes:
        ...
    def __next__(self) -> bytes:
        ...

class ValuesIterator(BaseIterator):
    def get(self) -> bytes:
        ...
    def __next__(self) -> bytes:
        ...


class ItemsIterator(BaseIterator):
    def get(self) -> Tuple[bytes, bytes]:
        ...
    def __next__(self) -> Tuple[bytes, bytes]:
        ...

# @cython.internal
# cdef class ReversedIterator(object):
#     cdef BaseIterator it

#     def __cinit__(self, BaseIterator it):
#         self.it = it

#     def seek_to_first(self):
#         self.it.seek_to_first()

#     def seek_to_last(self):
#         self.it.seek_to_last()

#     def seek(self, key):
#         self.it.seek(key)

#     def seek_for_prev(self, key):
#         self.it.seek_for_prev(key)

#     def get(self):
#         return self.it.get()

#     def __iter__(self):
#         return self

#     def __reversed__(self):
#         return self.it

#     def __next__(self):
#         if not self.it.ptr.Valid():
#             raise StopIteration()

#         cdef object ret = self.it.get_ob()
#         with nogil:
#             self.it.ptr.Prev()
#         check_status(self.it.ptr.status())
#         return ret

# cdef class BackupEngine(object):
#     cdef backup.BackupEngine* engine

#     def  __cinit__(self, backup_dir):
#         cdef Status st
#         cdef string c_backup_dir
#         self.engine = NULL

#         c_backup_dir = path_to_string(backup_dir)
#         st = backup.BackupEngine_Open(
#             env.Env_Default(),
#             backup.BackupEngineOptions(c_backup_dir),
#             cython.address(self.engine))

#         check_status(st)

#     def __dealloc__(self):
#         if not self.engine == NULL:
#             with nogil:
#                 del self.engine

#     def create_backup(self, DB db, flush_before_backup=False):
#         cdef Status st
#         cdef cpp_bool c_flush_before_backup

#         c_flush_before_backup = flush_before_backup

#         with nogil:
#             st = self.engine.CreateNewBackup(db.db, c_flush_before_backup)
#         check_status(st)

#     def restore_backup(self, backup_id, db_dir, wal_dir):
#         cdef Status st
#         cdef backup.BackupID c_backup_id
#         cdef string c_db_dir
#         cdef string c_wal_dir

#         c_backup_id = backup_id
#         c_db_dir = path_to_string(db_dir)
#         c_wal_dir = path_to_string(wal_dir)

#         with nogil:
#             st = self.engine.RestoreDBFromBackup(
#                 c_backup_id,
#                 c_db_dir,
#                 c_wal_dir)

#         check_status(st)

#     def restore_latest_backup(self, db_dir, wal_dir):
#         cdef Status st
#         cdef string c_db_dir
#         cdef string c_wal_dir

#         c_db_dir = path_to_string(db_dir)
#         c_wal_dir = path_to_string(wal_dir)

#         with nogil:
#             st = self.engine.RestoreDBFromLatestBackup(c_db_dir, c_wal_dir)

#         check_status(st)

#     def stop_backup(self):
#         with nogil:
#             self.engine.StopBackup()

#     def purge_old_backups(self, num_backups_to_keep):
#         cdef Status st
#         cdef uint32_t c_num_backups_to_keep

#         c_num_backups_to_keep = num_backups_to_keep

#         with nogil:
#             st = self.engine.PurgeOldBackups(c_num_backups_to_keep)
#         check_status(st)

#     def delete_backup(self, backup_id):
#         cdef Status st
#         cdef backup.BackupID c_backup_id

#         c_backup_id = backup_id

#         with nogil:
#             st = self.engine.DeleteBackup(c_backup_id)

#         check_status(st)

#     def get_backup_info(self):
#         cdef vector[backup.BackupInfo] backup_info

#         with nogil:
#             self.engine.GetBackupInfo(cython.address(backup_info))

#         ret = []
#         for ob in backup_info:
#             t = {}
#             t['backup_id'] = ob.backup_id
#             t['timestamp'] = ob.timestamp
#             t['size'] = ob.size
#             ret.append(t)

#         return ret
