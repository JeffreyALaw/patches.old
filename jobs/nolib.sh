#!/bin/sh -x

# If any command fails, exit immediately
set -e
set -o pipefail

TARGET=$1

NPROC=`nproc --all`

rm -rf ${TARGET}-obj
rm -rf ${TARGET}-installed
mkdir -p ${TARGET}-installed
mkdir -p ${TARGET}-obj/binutils
mkdir -p ${TARGET}-obj/gcc

# We only need the binutils-gdb and gcc trees
patches/jobs/setupsources.sh $TARGET binutils-gdb gcc

# Step 1, build binutils
cd ${TARGET}-obj/binutils
../../binutils-gdb/configure --prefix=`pwd`/../../${TARGET}-installed --target=${TARGET}
make -j $NPROC -l $NPROC all-gas all-binutils all-ld
make install-gas install-binutils install-ld
cd ../..
cd ${TARGET}-installed/bin
rm -f ar as ld ld.bfd nm objcopy objdump ranlib readelf strip
cd ../..

# Step 2, build gcc
PATH=`pwd`/${TARGET}-installed/bin:$PATH
cd ${TARGET}-obj/gcc
../../gcc/configure --disable-analyzer --with-system-libunwind --with-newlib --without-headers --disable-threads --disable-shared --enable-languages=c,c++ --prefix=`pwd`/../../${TARGET}-installed --target=${TARGET}
make -j $NPROC -l $NPROC all-gcc
make install-gcc

# We try to build and install libgcc, but don't consider a failure fatal
(make -j $NPROC -l $NPROC all-target-libgcc && make install-target-libgcc) || /bin/true
cd ../..

# The binutils suite is run unconditionally
cd ${TARGET}-obj/binutils
make -k -j $NPROC -l $NPROC check-gas check-ld check-binutils || true
cd ../..

patches/jobs/validate-results.sh $TARGET
