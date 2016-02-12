#!/usr/bin/env bash

CERT_PATH=${JENKINS_HOME}/certs

if [ ! -d ${CERT_PATH} ]; then
    echo "No TLS/SSL certs stored on server. Generating self-signed certs."
    mkdir -p ${CERT_PATH}

    TEMP_CERT_PATH=$(/usr/local/bin/generate-cert.sh)

    cp ${TEMP_CERT_PATH}/cert.pem ${CERT_PATH}
    cp ${TEMP_CERT_PATH}/key.pem ${CERT_PATH}

    chmod -R o-rwx ${CERT_PATH}

    rm -rf ${TEMP_CERT_PATH}
fi

if [ ! -f "${JENKINS_HOME}/first-started.txt" ]; then
    FIRST_BOOT=1
    date > ${JENKINS_HOME}/first-started.txt
else
    FIRST_BOOT=0
fi

# We setup a default user account so that there are no race conditions when
# creating your first Jenkins server on the cloud
if [ ${FIRST_BOOT} -eq 1 ]; then
    echo "Setting up Jenkins"

    cp -r /usr/share/jenkins/templates/config.xml ${JENKINS_HOME}
    mkdir -p ${JENKINS_HOME}/users/admin

    DEFAULT_PASSWD=$(dd if=/dev/urandom bs=9 count=1 2> /dev/null | base64 | tr -d "\n")
    API_TOKEN=$(dd if=/dev/urandom bs=64 count=1 2> /dev/null | base64 | tr -d "\n")
    HASH=$(echo -n "$DEFAULT_PASSWD"'{zil0}' | sha256sum | cut -d' ' -f1)

    echo "A default Jenkins user has been created with the credentials:"
    echo "login: admin password: $DEFAULT_PASSWD"
    echo "Once you login, be sure to change the credentials to your needs."

    xmlstarlet ed \
        -u '//passwordHash' -v "zil0:${HASH}" \
        -u '//apiToken' -v "${API_TOKEN}" \
        /usr/share/jenkins/templates/users/admin/config.xml \
        > ${JENKINS_HOME}/users/admin/config.xml

    echo "Setting up Jenkins SSHD to listen on port 22"
    cp /usr/share/jenkins/templates/org.jenkinsci.main.modules.sshd.SSHD.xml ${JENKINS_HOME}

    echo "Setting up Triton credentials"
    ssh-keygen -q -t rsa -N "" -b 2048 -f ~/.ssh/id_rsa

    echo "Add the following public key to your Triton account:"
    cat ~/.ssh/id_rsa.pub
    echo
    echo "You can do this in the Joyent portal by clicking on your name on the"
    echo "top right and choosing account or you can do this using the CLI with"
    echo "the smartdc tools by using the sdc-user command:"
    echo "    sdc-user upload-key user_id public_ssh_key"
    echo
    echo "Please go do this now. We will wait until you finish."
    echo
    read -rsp $'Press any key to continue...\n' -n1 key
    echo
    echo "We will now setup your Docker credentials and Triton settings."
    echo
    curl --retry 6 -sSL -f https://raw.githubusercontent.com/joyent/sdc-docker/master/tools/sdc-docker-setup.sh > /tmp/sdc-docker-setup.sh

    bash /tmp/sdc-docker-setup.sh -p jenkins "" "" ~/.ssh/id_rsa

    echo
    echo "Adding Triton Docker credentials to Jenkins"

    DOCKER_CREDENTIALS_ID="$(uuidgen -r)"

    xmlstarlet ed \
        -u '//com.nirima.jenkins.plugins.docker.utils.DockerDirectoryCredentials/id' -v ${DOCKER_CREDENTIALS_ID} \
        /usr/share/jenkins/templates/credentials.xml \
        > ${JENKINS_HOME}/credentials.xml

    xmlstarlet ed \
        -u '//com.nirima.jenkins.plugins.docker.DockerCloud/credentialsId' -v ${DOCKER_CREDENTIALS_ID} \
        /usr/share/jenkins/templates/config.xml \
        > ${JENKINS_HOME}/config.xml

    if [ "$1" == "install" ]; then
        echo "Setup finished. Please restart the container to run Jenkins."
        exit 0
    fi
fi

# We detect the amount of memory available on the machine and allocate 512mb as a buffer
TOTAL_MEMORY_KB=$(cat /proc/meminfo | grep MemTotal | cut -d: -f2 | sed 's/^ *//' | cut -d' ' -f1)
RESERVED_KB=512000
MAX_JVM_HEAP_KB=$(echo "8k $TOTAL_MEMORY_KB $RESERVED_KB - pq" | dc)

# If we are running on Triton, then we will tune the JVM for the platform
if [ -d /native ]; then
    HW_THREADS=$(/usr/local/bin/proclimit)

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
else
    JAVA_GC_FLAGS=""
fi

export _JAVA_OPTIONS="${JAVA_GC_FLAGS} -Xmx${MAX_JVM_HEAP_KB}K -Djava.net.preferIPv4Stack=true -Djava.awt.headless=true -Dhudson.DNSMultiCast.disabled=true"

exec authbind --deep /usr/local/bin/jenkins.sh \
    --httpsCertificate=${CERT_PATH}/cert.pem \
    --httpsPrivateKey=${CERT_PATH}/key.pem \
    --httpsPort=443 \
    "$@"
