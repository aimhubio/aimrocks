# distutils: language = c++

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

ctypedef const filter_policy.FilterPolicy ConstFilterPolicy

cdef extern from "rdb_include/utils.hpp" namespace "py_rocks":
    cdef const Slice* vector_data(vector[Slice]&)

cdef extern from "Python.h":
    void PyEval_InitThreads()

cdef check_status(const Status& st)

cdef string bytes_to_string(path) except *

cdef string_to_bytes(string ob)

cdef Slice bytes_to_slice(ob) except *

cdef slice_to_bytes(Slice sl)

cdef string path_to_string(object path) except *

cdef object string_to_path(string path)

cdef class PyComparator(object):
    cdef object get_ob(self)

    cdef const comparator.Comparator* get_comparator(self)

    cdef set_info_log(self, shared_ptr[logger.Logger] info_log)

cdef class PyGenericComparator(PyComparator):
    cdef comparator.ComparatorWrapper* comparator_ptr
    cdef object ob
    # def __cinit__(self, object ob)
    # def __dealloc__(self)
    cdef object get_ob(self)
    cdef const comparator.Comparator* get_comparator(self)
    cdef set_info_log(self, shared_ptr[logger.Logger] info_log)

cdef class PyBytewiseComparator(PyComparator):
    cdef const comparator.Comparator* comparator_ptr
    # def __cinit__(self)
    cpdef name(self)
    cpdef compare(self, a, b)
    cdef object get_ob(self)
    cdef const comparator.Comparator* get_comparator(self)


cdef int compare_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice& a,
    const Slice& b) with gil

# BytewiseComparator = PyBytewiseComparator
#########################################



## Here comes the stuff for the filter policy
cdef class PyFilterPolicy(object):
    cdef object get_ob(self)
    cdef shared_ptr[ConstFilterPolicy] get_policy(self)
    cdef set_info_log(self, shared_ptr[logger.Logger] info_log)

cdef class PyGenericFilterPolicy(PyFilterPolicy):
    cdef shared_ptr[filter_policy.FilterPolicyWrapper] policy
    cdef object ob
    # def __cinit__(self, object ob)
    cdef object get_ob(self)
    cdef shared_ptr[ConstFilterPolicy] get_policy(self)
    cdef set_info_log(self, shared_ptr[logger.Logger] info_log)


cdef void create_filter_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice* keys,
    int n,
    string* dst) with gil

cdef cpp_bool key_may_match_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice& key,
    const Slice& filt) with gil

cdef class PyBloomFilterPolicy(PyFilterPolicy):
    cdef shared_ptr[ConstFilterPolicy] policy
    # def __cinit__(self, int bits_per_key)
    cpdef name(self)
    cpdef create_filter(self, keys)
    cpdef key_may_match(self, key, filter_)
    cdef object get_ob(self)
    cdef shared_ptr[ConstFilterPolicy] get_policy(self)

# BloomFilterPolicy = PyBloomFilterPolicy
# #############################################



## Here comes the stuff for the merge operator
cdef class PyMergeOperator(object):
    cdef shared_ptr[merge_operator.MergeOperator] merge_op
    cdef object ob
    # def __cinit__(self, object ob)
    cdef object get_ob(self)
    cdef shared_ptr[merge_operator.MergeOperator] get_operator(self)

cdef cpp_bool merge_callback(
    void* ctx,
    const Slice& key,
    const Slice* existing_value,
    const Slice& value,
    string* new_value,
    logger.Logger* log) with gil

cdef cpp_bool full_merge_callback(
    void* ctx,
    const Slice& key,
    const Slice* existing_value,
    const deque[string]& op_list,
    string* new_value,
    logger.Logger* log) with gil

cdef cpp_bool partial_merge_callback(
    void* ctx,
    const Slice& key,
    const Slice& left_op,
    const Slice& right_op,
    string* new_value,
    logger.Logger* log) with gil

cdef class PyCache(object):
    cdef shared_ptr[cache.Cache] get_cache(self)

cdef class PyLRUCache(PyCache):
    cdef shared_ptr[cache.Cache] cache_ob
    # def __cinit__(self, capacity, shard_bits = *)
    cdef shared_ptr[cache.Cache] get_cache(self)

LRUCache = PyLRUCache
###############################

### Here comes the stuff for SliceTransform
cdef class PySliceTransform(object):
    cdef shared_ptr[slice_transform.SliceTransform] transfomer
    cdef object ob
    # def __cinit__(self, object ob)
    cdef object get_ob(self)
    cdef shared_ptr[slice_transform.SliceTransform] get_transformer(self)
    cdef set_info_log(self, shared_ptr[logger.Logger] info_log)


cdef Slice slice_transform_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice& src) with gil

cdef cpp_bool slice_in_domain_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice& src) with gil

cdef cpp_bool slice_in_range_callback(
    void* ctx,
    logger.Logger* log,
    string& error_msg,
    const Slice& src) with gil

## Here are the TableFactories
cdef class PyTableFactory(object):
    cdef shared_ptr[table_factory.TableFactory] factory
    cdef shared_ptr[table_factory.TableFactory] get_table_factory(self)
    cdef set_info_log(self, shared_ptr[logger.Logger] info_log)

cdef class BlockBasedTableFactory(PyTableFactory):
    cdef PyFilterPolicy py_filter_policy
    # def __init__(self,
    #         index_type='binary_search',
    #         py_bool hash_index_allow_collision=True,
    #         checksum='crc32',
    #         PyCache block_cache = *,
    #         PyCache block_cache_compressed = *,
    #         filter_policy = *,
    #         no_block_cache=False,
    #         block_size = *,
    #         block_size_deviation = *,
    #         block_restart_interval = *,
    #         whole_key_filtering = *)
    cdef set_info_log(self, shared_ptr[logger.Logger] info_log)

cdef class PlainTableFactory(PyTableFactory):
    pass
    # def __init__(
    #         self,
    #         user_key_len=0,
    #         bloom_bits_per_key=10,
    #         hash_table_ratio=0.75,
    #         index_sparseness=10,
    #         huge_page_tlb_size=0,
    #         encoding_type='plain',
    #         py_bool full_scan_mode=False)
#############################################

### Here are the MemtableFactories
cdef class PyMemtableFactory(object):
    cdef shared_ptr[memtablerep.MemTableRepFactory] factory
    cdef shared_ptr[memtablerep.MemTableRepFactory] get_memtable_factory(self)

cdef class SkipListMemtableFactory(PyMemtableFactory):
    pass
    # def __init__(self)

cdef class VectorMemtableFactory(PyMemtableFactory):
    pass
    # def __init__(self, count=0)

cdef class HashSkipListMemtableFactory(PyMemtableFactory):
    pass
    # def __init__(
    #         self,
    #         bucket_count=1000000,
    #         skiplist_height=4,
    #         skiplist_branching_factor=4)

cdef class HashLinkListMemtableFactory(PyMemtableFactory):
    pass
    # def __init__(self, bucket_count=50000)
##################################


cdef class CompressionType(object):
    pass
    # no_compression = u'no_compression'
    # snappy_compression = u'snappy_compression'
    # zlib_compression = u'zlib_compression'
    # bzip2_compression = u'bzip2_compression'
    # lz4_compression = u'lz4_compression'
    # lz4hc_compression = u'lz4hc_compression'
    # xpress_compression = u'xpress_compression'
    # zstd_compression = u'zstd_compression'
    # zstdnotfinal_compression = u'zstdnotfinal_compression'
    # disable_compression = u'disable_compression'

cdef class CompactionPri(object):
    pass
    # by_compensated_size = u'by_compensated_size'
    # oldest_largest_seq_first = u'oldest_largest_seq_first'
    # oldest_smallest_seq_first = u'oldest_smallest_seq_first'
    # min_overlapping_ratio = u'min_overlapping_ratio'

cdef class _ColumnFamilyHandle:
    """ This is an internal class that we will weakref for safety """
    cdef db.ColumnFamilyHandle* handle
    cdef object __weakref__
    cdef object weak_handle
    # def __cinit__(self)
    # def __dealloc__(self)
    @staticmethod
    cdef from_handle_ptr(db.ColumnFamilyHandle* handle)
    # @property
    # def name(self)
    # @property
    # def id(self)
    # @property
    # def weakref(self)

cdef class ColumnFamilyHandle:
    """ This represents a ColumnFamilyHandle """
    cdef object _ref
    cdef readonly bytes name
    cdef readonly int id
    # def __cinit__(self, weakhandle)
    # def __init__(self, *)
    @staticmethod
    cdef object from_wrapper(_ColumnFamilyHandle real_handle)
    # @property
    # cpdef is_valid(self)
    # def __repr__(self)
    cdef db.ColumnFamilyHandle* get_handle(self) except NULL
    # def __eq__(self, other)
    # def __lt__(self, other)
    # Since @total_ordering isn't a thing for cython
    # def __ne__(self, other)
    # def __gt__(self, other)
    # def __le__(self, other)
    # def __ge__(self, other)
    # def __hash__(self)

cdef class ColumnFamilyOptions(object):
    cdef options.ColumnFamilyOptions* copts
    cdef PyComparator py_comparator
    cdef PyMergeOperator py_merge_operator
    cdef PySliceTransform py_prefix_extractor
    cdef PyTableFactory py_table_factory
    cdef PyMemtableFactory py_memtable_factory

    # Used to protect sharing of Options with many DB-objects
    cdef cpp_bool in_use
    # def __cinit__(self)
    # def __dealloc__(self)
    # def __init__(self, **kwargs)
    # property write_buffer_size:
    #     def __get__(self)
    #     def __set__(self, value)
    # property max_write_buffer_number:
    #     def __get__(self)
    #     def __set__(self, value)
    # property min_write_buffer_number_to_merge:
    #     def __get__(self)
    #     def __set__(self, value)
    # property compression_opts:
    #     def __get__(self)
    #     def __set__(self, dict value)
    # property compaction_pri:
    #     def __get__(self)
    #     def __set__(self, value)
    # property compression:
    #     def __get__(self)
    #     def __set__(self, value)
    # property max_compaction_bytes:
    #     def __get__(self)
    #     def __set__(self, value)
    # property num_levels:
    #     def __get__(self)
    #     def __set__(self, value)
    # property level0_file_num_compaction_trigger:
    #     def __get__(self)
    #     def __set__(self, value)
    # property level0_slowdown_writes_trigger:
    #     def __get__(self)
    #     def __set__(self, value)
    # property level0_stop_writes_trigger:
    #     def __get__(self)
    #     def __set__(self, value)
    # property max_mem_compaction_level:
    #     def __get__(self)
    #     def __set__(self, value)
    # property target_file_size_base:
    #     def __get__(self)
    #     def __set__(self, value)
    # property target_file_size_multiplier:
    #     def __get__(self)
    #     def __set__(self, value)
    # property max_bytes_for_level_base:
    #     def __get__(self)
    #     def __set__(self, value)
    # property max_bytes_for_level_multiplier:
    #     def __get__(self)
    #     def __set__(self, value)
    # property max_bytes_for_level_multiplier_additional:
    #     def __get__(self)
    #     def __set__(self, value)
    # property arena_block_size:
    #     def __get__(self)
    #     def __set__(self, value)
    # property disable_auto_compactions:
    #     def __get__(self)
    #     def __set__(self, value)
    # # FIXME: remove to util/options_helper.h
    # #  property allow_os_buffer:
    #     #  def __get__(self):
    #         #  return self.copts.allow_os_buffer
    #     #  def __set__(self, value):
    #         #  self.copts.allow_os_buffer = value
    # property compaction_style:
    #     def __get__(self)
    #     def __set__(self, str value)
    # property compaction_options_universal:
    #     def __get__(self)
    #     def __set__(self, dict value)
    # # Deprecate
    # #  property filter_deletes:
    #     #  def __get__(self):
    #         #  return self.copts.filter_deletes
    #     #  def __set__(self, value):
    #         #  self.copts.filter_deletes = value
    # property max_sequential_skip_in_iterations:
    #     def __get__(self)
    #     def __set__(self, value)
    # property inplace_update_support:
    #     def __get__(self)
    #     def __set__(self, value)
    # property table_factory:
    #     def __get__(self)
    #     def __set__(self, PyTableFactory value)
    # property memtable_factory:
    #     def __get__(self)
    #     def __set__(self, PyMemtableFactory value)
    # property inplace_update_num_locks:
    #     def __get__(self)
    #     def __set__(self, value)
    # property comparator:
    #     def __get__(self)
    #     def __set__(self, value)
    # property merge_operator:
    #     def __get__(self)
    #     def __set__(self, value)
    # property prefix_extractor:
    #     def __get__(self)
    #     def __set__(self, value)

cdef class Options(ColumnFamilyOptions):
    cdef options.Options* opts
    cdef PyCache py_row_cache
    # def __cinit__(self)
    # def __dealloc__(self)
    # def __init__(self, **kwargs)
#     property create_if_missing:
#         def __get__(self)
#         def __set__(self, value)
#     property error_if_exists:
#         def __get__(self)
#         def __set__(self, value)
#     property paranoid_checks:
#         def __get__(self)
#         def __set__(self, value)
#     property max_open_files:
#         def __get__(self)
#         def __set__(self, value)
#     property use_fsync:
#         def __get__(self)
#         def __set__(self, value)
#     property db_log_dir:
#         def __get__(self)
#         def __set__(self, value)
#     property wal_dir:
#         def __get__(self)
#         def __set__(self, value)
#     property delete_obsolete_files_period_micros:
#         def __get__(self)
#         def __set__(self, value)
#     property max_background_compactions:
#         def __get__(self)
#         def __set__(self, value)
#     property max_background_flushes:
#         def __get__(self)
#         def __set__(self, value)
#     property max_log_file_size:
#         def __get__(self)
#         def __set__(self, value)
#     property db_write_buffer_size:
#         def __get__(self)
#         def __set__(self, value)
#     property log_file_time_to_roll:
#         def __get__(self)
#         def __set__(self, value)
#     property keep_log_file_num:
#         def __get__(self)
#         def __set__(self, value)
#     property max_manifest_file_size:
#         def __get__(self)
#         def __set__(self, value)
#     property table_cache_numshardbits:
#         def __get__(self)
#         def __set__(self, value)
#     property wal_ttl_seconds:
#         def __get__(self)
#         def __set__(self, value)
#     property wal_size_limit_mb:
#         def __get__(self)
#         def __set__(self, value)
#     property manifest_preallocation_size:
#         def __get__(self)
#         def __set__(self, value)
#     property enable_write_thread_adaptive_yield:
#         def __get__(self)
#         def __set__(self, value)
#     property allow_concurrent_memtable_write:
#         def __get__(self)
#         def __set__(self, value)
#     property allow_mmap_reads:
#         def __get__(self)
#         def __set__(self, value)
#     property allow_mmap_writes:
#         def __get__(self)
#         def __set__(self, value)
#     property is_fd_close_on_exec:
#         def __get__(self)
#         def __set__(self, value)
#     property stats_dump_period_sec:
#         def __get__(self)
#         def __set__(self, value)
#     property advise_random_on_open:
#         def __get__(self)
#         def __set__(self, value)
#   # TODO: need to remove -Wconversion to make this work
#   # property access_hint_on_compaction_start:
#   #     def __get__(sel
#   #     def __set__(self, AccessHint valu
#     property use_adaptive_mutex:
#         def __get__(self)
#         def __set__(self, value)
#     property bytes_per_sync:
#         def __get__(self)
#         def __set__(self, value)
#     property row_cache:
#         def __get__(self)
#         def __set__(self, value)
#     # cpp_bool skip_checking_sst_file_sizes_on_db_open
#     property skip_checking_sst_file_sizes_on_db_open:
#         def __get__(self)
#         def __set__(self, value)
#     # cpp_bool skip_stats_update_on_db_open
#     property skip_stats_update_on_db_open:
#         def __get__(self)
#         def __set__(self, value)

# Forward declaration
# cdef class Snapshot

# cdef class KeysIterator
# cdef class ValuesIterator
# cdef class ItemsIterator
# cdef class ReversedIterator

# # Forward declaration
# cdef class WriteBatchIterator

cdef class WriteBatch(object):
    cdef db.WriteBatch* batch

    # def __cinit__(self, data = *)
    # def __dealloc__(self)
    cpdef void put(self, bytes key, bytes value, ColumnFamilyHandle column_family = *)
    cpdef void merge(self, bytes key, bytes value, ColumnFamilyHandle column_family = *)
    cpdef void delete_single(self, bytes key, ColumnFamilyHandle column_family = *)
    cpdef void delete_range(self, bytes begin_key, bytes end_key, ColumnFamilyHandle column_family = *)
    cpdef void clear(self)
    cpdef data(self)
    cpdef int count(self)
    # def __iter__(self)

cdef class WriteBatchIterator(object):
    # Need a reference to the WriteBatch.
    # The BatchItems are only pointers to the memory in WriteBatch.
    cdef WriteBatch batch
    cdef vector[db.BatchItem] items
    cdef size_t pos
    # def __init__(self, WriteBatch batch)
    # def __iter__(self)
    # def __next__(self)

cdef class IDB(object):
    cpdef void put(self, bytes key, bytes value, cpp_bool sync = *, cpp_bool disable_wal = *, ColumnFamilyHandle column_family = *)
    cpdef void delete_single(self, bytes key, cpp_bool sync = *, cpp_bool disable_wal = *, ColumnFamilyHandle column_family = *)
    cpdef void delete_range(self, bytes begin_key, bytes end_key, cpp_bool sync = *, cpp_bool disable_wal = *, ColumnFamilyHandle column_family = *)
    cpdef void flush(self)
    cpdef void flush_wal(self, cpp_bool sync = *)
    cpdef void merge(self, bytes key, bytes value, cpp_bool sync = *, cpp_bool disable_wal = *, ColumnFamilyHandle column_family = *)
    cpdef void write(self, WriteBatch batch, cpp_bool sync = *, cpp_bool disable_wal = *)
    cpdef get(self, bytes key, ColumnFamilyHandle column_family = *)
    cpdef multi_get(self, keys)
    cpdef key_may_exist(self, bytes key, cpp_bool fetch = *, ColumnFamilyHandle column_family = *)
    cpdef Iterator iterkeys(self, ColumnFamilyHandle column_family = *)
    cpdef Iterator itervalues(self, ColumnFamilyHandle column_family = *)
    cpdef Iterator iteritems(self, ColumnFamilyHandle column_family = *)

@cython.no_gc_clear
cdef class DB(IDB):
    cdef Options opts
    cdef db.DB* db
    cdef list cf_handles
    cdef list cf_options
    # def __cinit__(self, db_name, Options opts, dict column_families = *, read_only=False)
    # def __dealloc__(self)
    cpdef void close(self)
    # @property
    # cpdef column_families(self)
    cpdef get_column_family(self, bytes name)
    cpdef iterskeys(self, column_families)
    cpdef itersvalues(self, column_families)
    cpdef itersitems(self, column_families)
    cpdef snapshot(self)
    cpdef get_property(self, prop, ColumnFamilyHandle column_family = *)
    cpdef get_live_files_metadata(self)
    cpdef void compact_range(
        self,
        bytes begin = *,
        bytes end = *,
        cpp_bool change_level = *,
        int target_level = *,
        str bottommost_level_compaction = *,
        ColumnFamilyHandle column_family = *
    )
    # @staticmethod
    # def __parse_read_opts(
    #     verify_checksums = *,
    #     fill_cache = *,
    #     snapshot = *,
    #     read_tier = *)
    cdef options.ReadOptions build_read_opts(self, dict py_opts)
    # property options:
    #     def __get__(self)
    cpdef create_column_family(self, bytes name, ColumnFamilyOptions copts)
    cpdef void drop_column_family(self, ColumnFamilyHandle weak_handle)

cpdef repair_db(db_name, Options opts)

cpdef list_column_families(db_name, Options opts)

@cython.no_gc_clear
cdef class Snapshot(object):
    cdef const snapshot.Snapshot* ptr
    cdef DB db

    # def __cinit__(self, DB db)
    # def __dealloc__(self)


cdef class Iterator:
    cdef object _current_value

    cpdef object next(self)
    cpdef object get(self)
    cpdef void skip(self)


cdef class BaseIterator(Iterator):
    cdef iterator.Iterator* ptr
    cdef DB db
    cdef ColumnFamilyHandle handle

    # def __cinit__(self, DB db, ColumnFamilyHandle handle = None)
    # def __dealloc__(self)
    # def __iter__(self)
    # def __next__(self)
    # def __reversed__(self)
    cpdef void seek_to_first(self)
    cpdef void seek_to_last(self)
    cpdef void seek(self, bytes key)
    cpdef void seek_for_prev(self, bytes key)
    cdef object get_ob(self)

cdef class KeysIterator(BaseIterator):
    cdef object get_ob(self)

cdef class ValuesIterator(BaseIterator):
    cdef object get_ob(self)

cdef class ItemsIterator(BaseIterator):
    cdef object get_ob(self)

cdef class ReversedIterator(Iterator):
    cdef BaseIterator it

    # def __cinit__(self, BaseIterator it)
    cpdef void seek_to_first(self)
    cpdef void seek_to_last(self)
    cpdef void seek(self, bytes key)
    cpdef void seek_for_prev(self, bytes key)
    # def __iter__(self)
    # def __reversed__(self)
    # def __next__(self)

cdef class BackupEngine(object):
    cdef backup.BackupEngine* engine

    # def  __cinit__(self, backup_dir)s
    # def __dealloc__(self)
    cpdef create_backup(self, DB db, flush_before_backup = *)
    cpdef restore_backup(self, backup_id, db_dir, wal_dir)
    cpdef restore_latest_backup(self, db_dir, wal_dir)
    cpdef stop_backup(self)
    cpdef purge_old_backups(self, num_backups_to_keep)
    cpdef delete_backup(self, backup_id)
    cpdef get_backup_info(self)
