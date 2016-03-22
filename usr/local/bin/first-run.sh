#!/usr/bin/env bash

if [ -f "${JENKINS_HOME}/first-started.txt" ]; then
    exit 0
fi

date > ${JENKINS_HOME}/first-started.txt
create_jenkins_user
docker_setup
docker_plugin_setup
setup_jenkins_home

# verify we're good-to-go
docker info

# We setup a default user account so that there are no race conditions when
# creating your first Jenkins server on the cloud
create_jenkins_user() {
    echo
    echo 'Setting up Jenkins user...'

    cp -r /usr/share/jenkins/templates/config.xml ${JENKINS_HOME}
    mkdir -p ${JENKINS_HOME}/users/admin

    DEFAULT_PASSWD=$(dd if=/dev/urandom bs=9 count=1 2> /dev/null | base64 | tr -d "\n")
    API_TOKEN=$(dd if=/dev/urandom bs=64 count=1 2> /dev/null | base64 | tr -d "\n")
    HASH=$(echo -n "$DEFAULT_PASSWD"'{zil0}' | sha256sum | cut -d' ' -f1)

    echo -e "A default Jenkins user has been created with the credentials:"
    echo -e "login: \e[1madmin\e[0m password: \e[1m$DEFAULT_PASSWD"
    echo -e "\e[0mOnce you login, be sure to change the credentials to your needs."

    xmlstarlet \
        ed \
        -u '//passwordHash' -v "zil0:${HASH}" \
        -u '//apiToken' -v "${API_TOKEN}" \
        /usr/share/jenkins/templates/users/admin/config.xml \
        > ${JENKINS_HOME}/users/admin/config.xml

    echo "Setting up Jenkins SSHD to listen on port 22"
    cp /usr/share/jenkins/templates/org.jenkinsci.main.modules.sshd.SSHD.xml ${JENKINS_HOME}
}


# uses the PRIVATE_KEY, SDC_URL, and SDC_ACCOUNT variables to point the Docker
# client to the Triton DC
# TODO: need to make sure this works for local development vs Docker machine too
docker_setup() {
    echo
    echo 'Setting up Triton credentials for launching Docker containers...'

    mkdir -p /var/jenkins_home/.ssh
    echo ${PRIVATE_KEY} | sed 's/#/\n/g' > /var/jenkins_home/.ssh/id_rsa
    chmod 400 /var/jenkins_home/.ssh/id_rsa
    ssh-keygen -y -f /var/jenkins_home/.ssh/id_rsa -N '' \
               > /var/jenkins_home/.ssh/id_rsa.pub

    echo 'Running Triton setup script using your credentials...'
    bash /tmp/sdc-docker-setup.sh ${SDC_URL} ${SDC_ACCOUNT} ~/.ssh/id_rsa
}

# adds the Triton Docker credentials to the Jenkins Docker plugin
docker_plugin_setup() {
    echo
    echo "Adding Triton Docker credentials to Jenkins..."

    DOCKER_CREDENTIALS_ID="$(uuidgen -r)"

    xmlstarlet \
        ed \
        -u '//com.nirima.jenkins.plugins.docker.utils.DockerDirectoryCredentials/id' -v ${DOCKER_CREDENTIALS_ID} \
        /usr/share/jenkins/templates/credentials.xml \
        > ${JENKINS_HOME}/credentials.xml

    xmlstarlet \
        ed \
        -u '//com.nirima.jenkins.plugins.docker.DockerCloud/credentialsId' -v ${DOCKER_CREDENTIALS_ID} \
        /usr/share/jenkins/templates/config.xml \
        > ${JENKINS_HOME}/config.xml
}


# Copy files from /usr/share/jenkins/ref into /var/jenkins_home
# So the initial JENKINS-HOME is set with expected content.
# Don't override, as this is just a reference setup, and use from UI
# can then change this, upgrade plugins, etc.
setup_jenkins_home() {
    echo
    echo 'Setting up reference home directory...'
    export -f copy_reference_file
    touch "${COPY_REFERENCE_FILE_LOG}" || (echo "Can not write to ${COPY_REFERENCE_FILE_LOG}. Wrong volume permissions?" && exit 1)
    echo "--- Copying files at $(date)" >> "$COPY_REFERENCE_FILE_LOG"
    find /usr/share/jenkins/ref/ -type f -exec bash -c "copy_reference_file '{}'" \;
}

copy_reference_file() {
    f="${1%/}"
    b="${f%.override}"
    echo "$f" >> "$COPY_REFERENCE_FILE_LOG"
    rel="${b:23}"
    dir=$(dirname "${b}")
    echo " $f -> $rel" >> "$COPY_REFERENCE_FILE_LOG"
    if [[ ! -e /var/jenkins_home/${rel} || $f = *.override ]]
    then
        echo "copy $rel to JENKINS_HOME" >> "$COPY_REFERENCE_FILE_LOG"
        mkdir -p "/var/jenkins_home/${dir:23}"
        cp -r "${f}" "/var/jenkins_home/${rel}";
        # pin plugins on initial copy
        [[ ${rel} == plugins/*.jpi ]] && touch "/var/jenkins_home/${rel}.pinned"
    fi;
}
