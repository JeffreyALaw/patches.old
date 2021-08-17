#!/bin/sh -x

# Ensure that we fail if any command fails
set -e
set -o pipefail

TARGET=$1

# Step #6, setup for artifact archiving and comparing testresults
rm -rf testresults
mkdir -p testresults
cp `find ${TARGET}-obj obj -name \*.sum -print` testresults

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

