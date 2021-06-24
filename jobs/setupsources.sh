#!/bin/sh -x
set -e
set -o pipefail

TARGET=$1
shift

# This script copies the requested sources from the docker
# volume, updates them from their appropriate upstreams, then
# applies ptaches
#
# The set of repos is passed in as arguments
for repo in $*; do
  case $repo in
    gcc)
      url=git://gcc.gnu.org/git/gcc.git
      ;;
    binutils-gdb)
      url=git://sourceware.org/git/binutils-gdb.git
      ;;
    newlib-cygwin)
      url=https://sourceware.org/git/newlib-cygwin.git
      ;;
    glibc)
      url=https://sourceware.org/git/glibc.git
      ;;
    linux)
      url=https://github.com/torvalds/linux.git
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
  
for tool in $*; do

  # Don't try to "patch" the chroots
  if [ "$tool" == "chroots" ]; then
    continue
  fi

  cd $tool
  if [ -f ../patches/$tool/TOREMOVE ]; then
    rm -f `cat ../patches/$tool/TOREMOVE`
  fi
  for patch in ../patches/$tool/*.patch; do
    patch -p1 < $patch
  done
  cd ..
done
