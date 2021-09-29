# aimrocks: python wrapper for rocksdb

`aimrocks` is a python package written in Cython, similar to [python-rocksdb](https://python-rocksdb.readthedocs.io/en/latest/).

It uses statically linked libraries for rocksdb and compression libraries it depends on, 
so `aimrocks` can be used out of the box (without requiring additional installation of any of those).

### Example usage

```python
import aimrocks

db_options = dict(
  create_if_missing=True,
  paranoid_checks=False,
)

db_path = '/tmp/example_db'
rocks_db = aimrocks.DB(db_path, aimrocks.Options(**db_options), read_only=False)

batch = aimrocks.WriteBatch()
batch.put(b'key_1', b'value_1')
batch.put(b'key_1', b'value_1')
...

rocks_db.write(batch)

```
