#!/bin/sh -x
TARGET=$1

NPROC=`nproc --all`

rm -rf ${TARGET}-obj
rm -rf ${TARGET}-installed
mkdir -p ${TARGET}-installed
mkdir -p ${TARGET}-obj/binutils
mkdir -p ${TARGET}-obj/gcc

# Step 0, setup source repositories & apply patches
for repo in patches binutils-gdb gcc
do
  case $repo in
    gcc)
      url=git://gcc.gnu.org/git/gcc.git
      ;;
    binutils-gdb)
      url=git://sourceware.org/git/binutils-gdb.git
      ;;
    patches)
      url=https://github.com/JeffreyALaw/patches
      ;;
    default)
      echo "Unknown repository"
      exit 1
      ;;
  esac
  
  # If we have the docker volume, then use tar to clone into
  # our local copy.  That's going to be much faster than git.
  # Then update the local copy with the latest bits.  Otherwise
  # just clone from upstream.
  if [ -d /home/jlaw/jenkins/docker-volume/$repo ]; then
    pushd /home/jlaw/jenkins/docker-volume
    tar cf - ./$repo | (cd /home/jlaw/jenkins/workspace/${TARGET} ; tar xf - )
    popd
    pushd $repo
    git checkout -q -- .
    git pull
    popd
  else
    pushd $repo
    git clone $url $repo
    popd
  fi
  
done
  
for tool in binutils-gdb gcc; do
  cd $tool
  if [ -f ../patches/$tool/TOREMOVE ]; then
    rm -f `cat ../patches/$tool/TOREMOVE`
  fi
  for patch in ../patches/$tool/*.patch; do
    patch -p1 < $patch
  done
  cd ..
done



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

# Step #4, setup for artifact archiving and comparing testresults
rm -rf testresults
mkdir -p testresults
cp `find ${TARGET}-obj -name \*.sum -print` testresults

if [ -f old-testresults/gas.sum.gz ]; then
  rm -f old-testresults/*.sum
  gunzip old-testresults/*.sum.gz
  gcc/contrib/compare_tests old-testresults testresults || exit 255
fi


# Step #5, cleanup the temporary bits
rm -rf ${TARGET}-obj
rm -rf ${TARGET}-installed
rm -rf old-testresults

# Step #6, compress testresults before archiving
cd testresults
gzip --best *.sum
