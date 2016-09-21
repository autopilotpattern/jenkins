#!/usr/bin/env sh

##
# When this script is invoked inside of a LX Brand Zone:
#
# This script returns a number representing a very conservative estimate of the 
# maximum number of processes or threads that you want to run within the zone 
# that invoked this script. Typically, you would take this value and define a
# multiplier that works well for your application.
#
# Otherwise:
# This script returns the number of cores reported by the OS.

# If we are on a LX Brand Zone calculation value using utilities only available in the /native
# directory
if [ -d /native ]; then
   /native/usr/bin/ksh93 -c 'echo $(($(/native/usr/bin/prctl -n zone.cpu-cap $$ | /native/usr/bin/grep privileged | /native/usr/bin/awk "{ print \$2 }") / 100))'
   exit 0
fi

# Linux calculation if you have nproc
if [ -n "$(which nproc)" ]; then 
  nproc
  exit 0
fi

# Linux more widely supported implementation
if [ -f /proc/cpuinfo ] && [ -n $(which wc) ]; then
  grep processor /proc/cpuinfo | wc -l
  exit 0
fi

# OS X calculation
if [ "$(uname)" == "Darwin" ]; then
  sysctl -n hw.ncpu
  exit 0
fi

# Fallback value if we can't calculate
echo 1

