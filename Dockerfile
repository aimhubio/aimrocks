ARG FROM=ubuntu

FROM ${FROM} AS deps

RUN mkdir -p /opt/aimrocks_deps/lib /opt/aimrocks_deps/include
ENV AIM_DEP_DIR=/opt/aimrocks_deps
RUN /opt/python/cp37-cp37m/bin/python -m pip install cmake && \
    ln -s /opt/python/cp37-cp37m/bin/cmake /usr/bin/cmake
WORKDIR /opt/aimrocks_deps/



FROM build_base AS build_deps

COPY docker/build-zlib.sh ./
RUN ./build-zlib.sh

COPY docker/build-bzip2.sh ./
RUN ./build-bzip2.sh

COPY docker/build-zstd.sh ./
RUN ./build-zstd.sh

COPY docker/build-lz4.sh ./
RUN ./build-lz4.sh

COPY docker/build-snappy.sh ./
RUN ./build-snappy.sh



FROM deps AS rocksdb

COPY docker/build-rocksdb.sh ./
COPY deps/rocksdb_sched.patch /opt/aimrocks_deps/
RUN ./build-rocksdb.sh


FROM rocksdb AS wheels

COPY . /opt/aimrocks
COPY docker/build-wheels.sh ./
RUN ./build-wheels.sh


FROM rocksdb AS audit

COPY docker/audit-wheels.sh ./
RUN ./audit-wheels.sh
