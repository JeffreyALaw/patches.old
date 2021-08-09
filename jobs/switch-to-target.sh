#!/bin/bash
TARGET=$1

# This is much more complex than it should be because we can't mount
# in a swarm container, nor can we twiddle the container name based
# on the target/job.
#
# Instead we start the wrapper container, then morph it into a native
# container.  Egad.
#
# First move all the necessary bits from /usr/lib64 into
# /usr/lib64/x86_64, leaving behind just enough (ld.so) that
# things still work
mkdir /x86_64
cd /usr/lib64
tar cf - . | (cd /x86_64 ; tar xf - )
mv /x86_64 .
rm -rf `ls | grep -v ld- | grep -v x86_64`

# Now extract the chroot on top of ourselves, this may well fail due
# to some bits in /usr/lib64.  That's OK, we'll fix it up in a moment
cd /
tar xf /home/jlaw/jenkins/workspace/$TARGET/chroots/$TARGET.tar.xz --strip-components=2 --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' || true

# Now we're mostly in the target environment.  Clean up /usr/lib64 a bit.
# The trickiest bit here is the dynamic linker which we do not want to overwrite
rm /usr/lib64/ld-2.33.so
rm /etc/ld.so.cache
mv /usr/lib64/* /usr/lib
rm -rf /usr/lib64

# We just need to reinstante /usr/lib64
ln -s /usr/lib /usr/lib64
