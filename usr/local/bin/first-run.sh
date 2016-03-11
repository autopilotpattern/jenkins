#!/usr/bin/env bash

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

    echo -e "\e[1mA default Jenkins user has been created with the credentials:"
    echo -e "login: \e[32madmin\e[0m\e[1mA password: \e[1mA\e[32m$DEFAULT_PASSWD"
    echo -e "\e[0m\e[1mAOnce you login, be sure to change the credentials to your needs.\e[0m"

    xmlstarlet ed \
        -u '//passwordHash' -v "zil0:${HASH}" \
        -u '//apiToken' -v "${API_TOKEN}" \
        /usr/share/jenkins/templates/users/admin/config.xml \
        > ${JENKINS_HOME}/users/admin/config.xml

    echo "Setting up Jenkins SSHD to listen on port 22"
    cp /usr/share/jenkins/templates/org.jenkinsci.main.modules.sshd.SSHD.xml ${JENKINS_HOME}

    echo "Setting up Triton credentials"
    ssh-keygen -q -t rsa -N "" -b 2048 -f ~/.ssh/id_rsa

    echo -e "\e[0m\e[1mAAdd the following public key to your Triton account:"
    cat ~/.ssh/id_rsa.pub
    echo -e "\e[0m"
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
