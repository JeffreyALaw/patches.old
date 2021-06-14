#!/bin/sh -x
TARGET=$1


NPROC=`nproc --all`
PATH=~/bin/:$PATH

export GENERATION=2
echo $GENERATION

rm -rf ${TARGET}-obj
mkdir -p ${TARGET}-installed
mkdir -p ${TARGET}-obj/binutils
mkdir -p ${TARGET}-obj/gcc
mkdir -p ${TARGET}-obj/linux
mkdir -p ${TARGET}-obj/glibc

export RUNGCCTESTS=no

patches/jobs/setupsources.sh ${TARGET} binutils-gdb gcc glibc linux

# Step 1, build binutils
cd ${TARGET}-obj/binutils
../../binutils-gdb/configure --prefix=`pwd`/../../${TARGET}-installed --target=${TARGET}
make -j $NPROC -l $NPROC all-gas all-binutils all-ld
make install-gas install-binutils install-ld
cd ../..
cd ${TARGET}-installed/bin
rm -f ar as ld ld.bfd nm objcopy objdump ranlib readelf strip
cd ../..

export SHARED=
if [ \! `find ${TARGET}-installed -name crti.o` ]; then
  SHARED=--disable-shared
fi

# Step 2, build gcc
PATH=`pwd`/${TARGET}-installed/bin:$PATH
cd ${TARGET}-obj/gcc
../../gcc/configure $SHARED --disable-analyzer --disable-multilib --without-headers --disable-threads --enable-languages=c,c++ --prefix=`pwd`/../../${TARGET}-installed --target=${TARGET}
make -j $NPROC -l $NPROC all-gcc
make install-gcc

# Step 2.1, build and install libgcc.  This is separate from the other libraries because
# it should always work.  Other libraries may not work the first time we build on a host
# because the target headers, crt files, etc from glibc are not yet available.
make -j $NPROC -l $NPROC all-target-libgcc
make install-target-libgcc

# Step 2.2.  If it looks like we have crt files, then build libstdc++-v3
if [ -f ../../${TARGET}-installed/${TARGET}/lib/crt1.o ]; then
  make -j $NPROC -l $NPROC all-target-libstdc++-v3
  make install-target-libstdc++-v3
fi

cd ../..


# Step 3, build kernel headers, kernel modules and kernel itself
export KERNEL_TARGETS="all modules"
export KERNEL=true
export CONFIG=defconfig
export STRIPKGDBCONFIG=no

case "${TARGET}" in
   
  arm*-* | arm*-*-* | arm*-*-*-*)
    export ARCH=arm
    ;;
    
  csky*-* | csky*-*-* | csky-*-*-*-*)
  	export ARCH=csky
    export KERNEL=false
    ;;
   
  microblaze*-* | microblaze*-*-* | microblaze*-*-*-*)
    export ARCH=microblaze
    export STRIPKGDBCONFIG=yes
    ;;
    
  mips64-*-*)
    export ARCH=mips
    export CONFIG=64r1_defconfig
    ;;
    
  mips64el-*-*)
    export ARCH=mips
    export CONFIG=64r1el_defconfig
    ;;
    
  mips*-* | mips*-*-* | mips*-*-*-*)
    export ARCH=mips
    ;;
    
  nios*-* | nios*-*-* | nios*-*-*-*)
    export ARCH=nios2
    ;;
    
  powerpc*-* | powerpc*-*-* | powerpc*-*-*-*)
    export ARCH=powerpc
    CONFIG=pmac32_defconfig
    ;;
    
   
  s390*-* | s390*-*-* | s390*-*-*-*)
    export ARCH=s390
    ;;
    
  sh*-* | sh*-*-* | sh*-*-*-*)
    export ARCH=sh
    ;;
    
  *)
    /bin/false
    ;;
esac

cd ${TARGET}-obj/linux
make -C ../../linux O=${TARGET} ARCH=${ARCH} INSTALL_HDR_PATH=../../${TARGET}-installed/${TARGET} headers_install

if [ $KERNEL == "true" ]; then
  make -C ../../linux O=${TARGET} ARCH=${ARCH} mrproper
  make -C ../../linux O=${TARGET} ARCH=${ARCH} CROSS_COMPILE=${TARGET}- -j $NPROC -l $NPROC $CONFIG
  if [ $STRIPKGDBCONFIG == "yes" ]; then
    sed -i -e s/CONFIG_KGDB=y/CONFIG_KGDB=n/ ../../linux/${TARGET}/.config
  fi
  make -C ../../linux O=${TARGET} ARCH=${ARCH} CROSS_COMPILE=${TARGET}- -j $NPROC -l $NPROC $KERNEL_TARGETS
fi

cd ../..



# Step 4, build glibc
cd ${TARGET}-obj/glibc
../../glibc/configure --prefix=`pwd`/../../${TARGET}-installed/${TARGET} --build=x86_64-linux-gnu --host=${TARGET} --enable-add-ons
make -j $NPROC -l $NPROC 
make install
cd ../..

# Step 5, run tests
cd ${TARGET}-obj/binutils
make -k -j $NPROC -l $NPROC check-gas check-ld check-binutils || true
cd ../..

# Step 5, conditionally run the GCC testsuite using the simulator
if [ $DUMMY_SIM = "yes" ]; then
  rm -f ${TARGET}-installed/bin/${TARGET}-run
  gcc -O2 patches/support/dummy.c -o ${TARGET}-installed/bin/${TARGET}-run
  cd ${TARGET}-obj/gcc/gcc
  make site.exp
  echo lappend boards_dir "`pwd`/../../../patches/support" >> site.exp
  cd ../../../
fi

cd ${TARGET}-obj/gcc/gcc

if [ x"$RUNGCCTESTS" = x"yes" ]; then
  make -k -j $NPROC -l $NPROC check-gcc RUNTESTFLAGS="$TESTARGS"
fi

cd ../../..

# Step #6, setup for artifact archiving and comparing testresults
rm -rf testresults
mkdir -p testresults
cp `find ${TARGET}-obj -name \*.sum -print` testresults

if [ -f old-testresults/gas.sum ]; then
  gcc/contrib/compare_tests old-testresults testresults
fi


