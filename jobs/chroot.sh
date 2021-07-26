#!/bin/sh -x
set -e
set -o pipefail
TARGET=$1

# We need the binutils-gdb, gcc, glibc, linux & chroot trees
# This should be done before we start the nested container
# so that these can be mounted inside the nested container
patches/jobs/setupsources.sh $TARGET binutils-gdb gcc glibc linux chroots


# Now start up the nested container, with appropriate bind mounts
# to expose the sources and critically the next job stage script
# Run the nested container with enough privs to mount filesystems
# docker run -it 172.31.0.149:5000/gcc-chroot-riscv64-linux-gnu /bin/bash
docker run -v "$(pwd)"/patches:/home/jlaw/jenkins/workspace/$TARGET/patches --privileged 172.31.0.149:5000/gcc-chroot-$TARGET ls -l /home/jlaw/jenkins/workspace/$TARGET/patches

exit 0


NPROC=`nproc --all`
export QEMU_UNAME=4.15



# Now use our docker to instantiate the chroot, giving the nested container
# enough privileges to mount stuff


sudo rm -rf rootfs
mkdir -p rootfs
tar xf chroots/${TARGET}.tar.xz

cat << EOF > rootfs/tmp/mounts
#!/bin/sh -x
export LD_LIBRARY_PATH=/lib64:/usr/lib64:/lib:/usr/lib
whoami
#/bin/mount -t devtmpfs devtmpfs /dev
#/bin/mount -t devpts devpts /dev/pts
#/bin/mount -t proc proc /proc
EOF

ls -slag rootfs/
sleep 6000

mount --bind /proc rootfs/proc
mount --bind /dev rootfs/dev
mount --bind /dev/pts rootfs/dev/pts
exit 0

sudo /sbin/chroot rootfs /bin/sh /tmp/mounts
sudo mount --bind binutils-gdb rootfs/src/binutils
sudo mount --bind gcc rootfs/src/gcc
sudo mount --bind glibc rootfs/src/glibc
sudo mount --bind linux rootfs/src/linux

rm -rf rootfs/tmp/obj
mkdir -p rootfs/tmp/obj/{binutils,gcc,glibc,linux}

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

# Step 2, set up build scripts.
cat << EOF > rootfs/tmp/binutils.build
#!/bin/sh
export QEMU_UNAME=4.15
export LD_LIBRARY_PATH=/lib64:/usr/lib64:/lib:/usr/lib
if [ -L "/usr/bin/awk" ]; then
  rm /usr/bin/awk
  ln -s /usr/bin/gawk /usr/bin/awk
fi
cd /tmp/obj/binutils
/src/binutils/configure --prefix=/usr ${TARGET}
make -j $NPROC -l $NPROC all-gas all-binutils all-ld
make -k -j $NPROC -l $NPROC check-gas check-binutils check-ld || true
make install-gas install-binutils install-ld
EOF

cat << EOF > rootfs/tmp/gcc.build
#!/bin/sh
export QEMU_UNAME=4.15
export LD_LIBRARY_PATH=/lib64:/usr/lib64:/lib:/usr/lib
cd /tmp/obj/gcc
/src/gcc/configure --prefix=/usr --disable-analyzer --enable-languages=c,c++ --disable-multilib ${TARGET} $GCC_CONFIG
make -j $NPROC -l $NPROC
(cd gcc; make -j $NPROC -l $NPROC -k check-gcc || true)
make -k install || true
EOF


cat << EOF > rootfs/tmp/linux.build
#!/bin/sh
export QEMU_UNAME=4.15
export LD_LIBRARY_PATH=/lib64:/usr/lib64:/lib:/usr/lib
cd /tmp/obj/linux
make -C /src/linux O=/tmp/obj/linux mrproper
make -C /src/linux O=/tmp/obj/linux -j $NPROC -l $NPROC $KERNEL_CONFIG
make -C /src/linux O=/tmp/obj/linux -j $NPROC -l $NPROC $KERNEL_TARGETS
EOF

cat << EOF > rootfs/tmp/glibc.build
#!/bin/sh
export QEMU_UNAME=4.15
export LD_LIBRARY_PATH=/lib64:/usr/lib64:/lib:/usr/lib
cd /tmp/obj/glibc
/src/glibc/configure --prefix=/ --enable-add-ons
make -j $NPROC -l $NPROC 
#make install
EOF

# Step #3, run the scripts

sudo /sbin/chroot rootfs /bin/sh /tmp/binutils.build

sudo /sbin/chroot rootfs /bin/sh /tmp/gcc.build

sudo /sbin/chroot rootfs /bin/sh /tmp/glibc.build

sudo /sbin/chroot rootfs /bin/sh /tmp/linux.build

rm -rf testresults
mkdir -p testresults
cp `find rootfs/tmp/obj -name \*.sum -print` testresults

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

sudo rm -rf rootfs/tmp/obj/*
sudo rm -rf old-testresults

cd testresults
gzip --best *.sum
