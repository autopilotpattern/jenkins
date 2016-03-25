#!/usr/bin/env bash

# If we are running on Triton, then we will tune the JVM for the platform
if [ -d /native ]; then
    HW_THREADS=$(/usr/local/bin/proclimit.sh)

    # We allocate +1 extra thread in order to utilize bursting better
    if [ $HW_THREADS -le 8 ]; then
        GC_THREADS=$(echo "8k $HW_THREADS 1 + pq" | dc)
    else
        # ParallelGCThreads = (ncpus <= 8) ? ncpus : 3 + ((ncpus * 5) / 8)
        ADJUSTED=$(echo "8k $HW_THREADS 5 * pq" | dc)
        DIVIDED=$(echo "8k $ADJUSTED 8 / pq" | dc)
        GC_THREADS=$(echo "8k $DIVIDED 3 + pq" | dc | awk 'function ceil(valor) { return (valor == int(valor) && value != 0) ? valor : int(valor)+1 } { printf "%d", ceil($1) }')
    fi

    JAVA_GC_FLAGS="-XX:-UseGCTaskAffinity -XX:-BindGCTaskThreadsToCPUs -XX:ParallelGCThreads=${GC_THREADS}"

    # We detect the amount of memory available on the machine and allocate 512mb as a buffer
    TOTAL_MEMORY_KB=$(cat /proc/meminfo | grep MemTotal | cut -d: -f2 | sed 's/^ *//' | cut -d' ' -f1)
    RESERVED_KB=512000
    MAX_JVM_HEAP_KB=$(echo "8k $TOTAL_MEMORY_KB $RESERVED_KB - pq" | dc)

    MEMORY_SETTINGS="-Xmx${MAX_JVM_HEAP_KB}K"
else
    JAVA_GC_FLAGS=""
    MEMORY_SETTINGS=""
fi

JAVA_OPTS="${JAVA_GC_FLAGS} ${MEMORY_SETTINGS} -Djava.net.preferIPv4Stack=true -Djava.awt.headless=true -Dhudson.DNSMultiCast.disabled=true"

authbind --deep java $JAVA_OPTS \
         -jar /usr/share/jenkins/jenkins.war \
         --httpPort=80 $JENKINS_OPTS
