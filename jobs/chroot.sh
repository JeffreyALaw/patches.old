#!/bin/sh -x
export LD_LIBRARY_PATH=/lib64:/usr/lib64:/lib:/usr/lib
TARGET=$1
NPROC=`nproc --all`
export QEMU_UNAME=4.15

set -e
set -o pipefail

# We only need the binutils-gdb and gcc trees
patches/jobs/setupsources.sh $TARGET binutils-gdb gcc glibc linux chroots

# We are currently running native.  Switch to the target environment
patches/jobs/switch-to-target.sh $TARGET

# Light setup, this should move into the chroot at some point
if [ -L "/usr/bin/awk" ]; then
  rm /usr/bin/awk
  ln -s /usr/bin/gawk /usr/bin/awk
fi

rm -rf obj
mkdir -p obj/{binutils-gdb,gcc,glibc,linux}

export KERNEL_TARGETS="all modules"
export KERNEL_CONFIG=defconfig
export GCC_CONFIG=""

case ${TARGET} in
  riscv*-* | riscv*-*-* | riscv*-*-*-*)
    KERNEL_TARGETS=all
    ;;
  powerpc-* | powerpc-*-* | powerpc-*-*-*)
    KERNEL_CONFIG=pmac32_defconfig
    ;;
  arm-linux-gnueabihf)
    GCC_CONFIG="--with-arch=armv7-a --with-float=hard --with-fpu=vfpv3-d16 --with-abi=aapcs-linux"
    ;;
  mips*-*-*)
  	KERNEL_TARGETS="vmlinux modules"
    ;;
  *)
    /bin/true
    ;;
esac

pushd obj/binutils-gdb
../../binutils-gdb/configure --prefix=/usr ${TARGET}
make -j $NPROC -l $NPROC all-gas all-binutils all-ld
make -k -j $NPROC -l $NPROC check-gas check-binutils check-ld || true
make install-gas install-binutils install-ld
popd

pushd obj/gcc
../../gcc/configure --prefix=/usr --disable-analyzer --enable-languages=c,c++ --disable-multilib ${TARGET} $GCC_CONFIG
make -j $NPROC -l $NPROC
(cd gcc; make -j $NPROC -l $NPROC -k check-gcc || true)
make -k install || true
popd


pushd obj/linux
make -C ../../linux O=`pwd` mrproper
make -C ../../linux O=`pwd` -j $NPROC -l $NPROC $KERNEL_CONFIG
make -C ../../linux O=`pwd` -j $NPROC -l $NPROC $KERNEL_TARGETS
popd

pushd obj/glibc
../../glibc/configure --prefix=/ --enable-add-ons
make -j $NPROC -l $NPROC 
#make install

rm -rf testresults
mkdir -p testresults
cp `find obj -name \*.sum -print` testresults

newbase=`grep ${TARGET} patches/gcc/NEWBASELINES || true`
if [ -f old-testresults/gas.sum.gz ]; then
  rm -f old-testresults/*.sum
  gunzip old-testresults/*.sum.gz
  if [ "x$newbase" == "x" ]; then
    gcc/contrib/compare_tests old-testresults testresults
  else
    gcc/contrib/compare_tests old-testresults testresults || true
  fi
fi

cd testresults
gzip --best *.sum
