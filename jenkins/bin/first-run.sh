#!/usr/bin/env bash
set -e -o pipefail

JENKINS_HOME=/var/jenkins_home

# Set up the Jenkins admin user account
setup_jenkins_user() {
    echo 'setting up Jenkins admin user'
    : "${JENKINS_PASSWD:?Missing environment value for JENKINS_PASSWD. Exiting.}"
    : "${JENKINS_API_TOKEN:?Missing environment value for JENKINS_API_TOKEN. Exiting.}"

    mkdir -p "${JENKINS_HOME}/users/admin"

    HASH=$(echo -n "$JENKINS_PASSWD"'{zil0}' | sha256sum | cut -d' ' -f1)

    echo -e "A default Jenkins user has been created with the credentials:"
    echo -e "login: \e[1madmin\e[0m password: \e[1m$JENKINS_PASSWD"
    echo -e "\e[0mOnce you login, be sure to change the credentials to your needs."

    echo 'writing Jenkins admin user config'
    sed "s|JENKINS_API_TOKEN|${JENKINS_API_TOKEN}|" \
        /usr/share/jenkins/templates/users/admin/config.xml | \
        sed "s|JENKINS_PASSWORD_HASH|zil0:${HASH}|" \
            > "${JENKINS_HOME}/users/admin/config.xml"

}

setup_jenkins_ssh() {
    echo 'setting up Jenkins SSHD'
    cp /usr/share/jenkins/templates/org.jenkinsci.main.modules.sshd.SSHD.xml "${JENKINS_HOME}"
}


# write the Triton account ID to the Docker plugin config in config.xml
setup_triton_jenkins_config() {
    : "${TRITON_ACCOUNT:?TRITON_ACCOUNT not set}"
    if [ -f "${JENKINS_HOME}/config.xml" ]; then
        echo 'Jenkins ~/config.xml already configured'
        return
    fi
    echo "writing Triton account and GitHub OAuth info to Jenkins ~/config.xml"
    sed "s/TRITON_ACCOUNT/${TRITON_ACCOUNT}/g" \
        /usr/share/jenkins/templates/config.xml | \
        sed "s/GITHUB_OAUTH_CLIENT_ID/${GITHUB_OAUTH_CLIENT_ID}/" |\
        sed "s/GITHUB_OAUTH_SECRET/${GITHUB_OAUTH_SECRET}/" \
            > "${JENKINS_HOME}/config.xml"
}



# Run the Triton setup to point the Docker client at Triton datacenters
setup_triton_docker_config() {

    if [ -f "/var/jenkins_home/.sdc/docker/${SDC_ACCOUNT}" ]; then
        echo 'Triton credentials already configured'
        return
    fi
    echo 'setting up Triton credentials for launching Docker containers'

    if [ ! -f "${JENKINS_HOME}/.ssh/triton" ]; then
        echo "Mising Triton ssh key at ${JENKINS_HOME}/.ssh/triton"
        exit 1
    fi

    ssh-keygen -y -f "${JENKINS_HOME}/.ssh/triton" -N '' \
               > "${JENKINS_HOME}/.ssh/triton.pub"

    echo 'running Triton setup script using your credentials...'
    bash /usr/local/bin/sdc-docker-setup.sh "${SDC_URL}" "${SDC_ACCOUNT}" ~/.ssh/triton
}


# add GitHub credentials to the Jenkins plugins
setup_github_credentials() {
    : "${GITHUB_API_TOKEN:?Missing environment value for GITHUB_API_TOKEN}"
    : "${GITHUB_HOOK_TOKEN:?Missing environment value for GITHUB_HOOK_TOKEN}"

    sed "s/GITHUB_API_TOKEN/${GITHUB_API_TOKEN}/" \
        /usr/share/jenkins/templates/credentials.xml | \
        sed "s/GITHUB_HOOK_TOKEN/${GITHUB_HOOK_TOKEN}/" \
            > "${JENKINS_HOME}/credentials.xml"

    # trust GitHub key
    ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
}


# Copy files from /usr/share/jenkins/ref into ${JENKINS_HOME}
# So the initial JENKINS_HOME is set with expected content.
# Don't override, as this is just a reference setup, and use from UI
# can then change this, upgrade plugins, etc.
setup_plugins() {
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
    if [[ ! -e ${JENKINS_HOME}/${rel} || $f = *.override ]]
    then
        echo "copy $rel to JENKINS_HOME" >> "$COPY_REFERENCE_FILE_LOG"
        mkdir -p "${JENKINS_HOME}/${dir:23}"
        cp -r "${f}" "${JENKINS_HOME}/${rel}";
        # pin plugins on initial copy
        [[ ${rel} == plugins/*.jpi ]] && touch "${JENKINS_HOME}/${rel}.pinned"
    fi;
}


setup_bootstrap_job() {
    echo 'creating bootstrapping Jenkins job'
    mkdir -p "${JENKINS_HOME}/jobs/jenkins-jobs"

    sed "s|GITHUB_JOBS_REPO|${GITHUB_JOBS_REPO}|" \
        /usr/share/jenkins/templates/jenkins-jobs.config.xml | \
        sed "s|GITHUB_JOBS_SPEC|${GITHUB_JOBS_SPEC:-'master'}|" \
            > "${JENKINS_HOME}/jobs/jenkins-jobs/config.xml"
}


# ---------------------------------------------------
# parse arguments

cmd=$1
if [ -z "${cmd}" ]; then

    # this setup shouldn't run again if we're just restarting the container
    if [ -f "${JENKINS_HOME}/first-started.txt" ]; then
        echo 'Jenkins has already been setup'
        exit 0
    fi
    date > "${JENKINS_HOME}/first-started.txt"

    setup_jenkins_user
    setup_jenkins_ssh
    setup_triton_jenkins_config
    setup_triton_docker_config
    setup_github_credentials
    setup_plugins
    setup_bootstrap_job

    # verify we're good-to-go
    docker info
    exit
fi
echo "[DEBUG] running ${cmd} only"
shift
$cmd "${@}"
