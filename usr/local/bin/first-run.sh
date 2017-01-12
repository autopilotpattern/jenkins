#!/usr/bin/env bash

set -e

# Use the AppRole credentials to login to Vault. This provides a renewable
# token-granting-token that we'll use to get tokens for jobs.
login_vault_jenkins() {
    if [ -f ${JENKINS_HOME}/jenkinsToken ]; then
        echo 'already logged into Vault as as jenkins'
    else
        echo 'logging into Vault as as jenkins'
        _login_vault ${VAULT_ROLE_ID} ${VAULT_SECRET_ID} ${JENKINS_HOME}/jenkinsToken
    fi
    jenkinsToken=$(cat ${JENKINS_HOME}/jenkinsToken)
}

# Use the token we got for Jenkins to log in using the jenkins-job AppRole.
# We can use this token to grant limited tokens for jobs.
login_vault_jobs() {
    if [ -f ${JENKINS_HOME}/jenkinsJobToken ]; then
        echo 'already logged into Vault as as jenkin-job'
        return
    fi
    echo 'logging into Vault as as jenkins-job'
    local secret=$(curl -sL --fail -XPOST \
                        --cacert /usr/local/share/ca-certificates/ca_cert.pem \
                        -H "X-Vault-Token: ${jenkinsToken}" \
                        "https://vault:8200/v1/auth/approle/role/jenkins-job/secret-id" \
                          | jq -r .data.secret_id)
    local role=$(curl -sL --fail \
                      --cacert /usr/local/share/ca-certificates/ca_cert.pem \
                      -H "X-Vault-Token: ${jenkinsToken}" \
                      "https://vault:8200/v1/auth/approle/role/jenkins-job/role-id" \
                        | jq -r .data.role_id)

    _login_vault ${role} ${secret} ${JENKINS_HOME}/jenkinsJobToken
}

_login_vault() {
    local login=$(printf '{"role_id":"%s","secret_id":"%s"}' \
                         "${1}" "${2}")
    curl -sL --fail -XPOST -d ${login} \
         --cacert /usr/local/share/ca-certificates/ca_cert.pem \
         "https://vault:8200/v1/auth/approle/login" \
        | jq -r .auth.client_token > "${3}"
    chmod 400 "${3}"
    echo "wrote Vault token to ${3}"
}


# We setup a default user account so that there are no race conditions when
# creating your first Jenkins server on the cloud
setup_jenkins_user() {
    echo 'setting up Jenkins admin user'

    cp -r /usr/share/jenkins/templates/config.xml ${JENKINS_HOME}
    mkdir -p ${JENKINS_HOME}/users/admin

    JENKINS_PASSWD=${JENKINS_PASSWD:-$(curl -sL --fail \
         --cacert /usr/local/share/ca-certificates/ca_cert.pem \
         -H "X-Vault-Token: ${jenkinsToken}" \
         "https://vault:8200/v1/secret/jenkins/password" | jq -r .data.value)}

    JENKINS_API_TOKEN=${JENKINS_API_TOKEN:-$(curl -sL --fail \
         --cacert /usr/local/share/ca-certificates/ca_cert.pem \
         -H "X-Vault-Token: ${jenkinsToken}" \
         "https://vault:8200/v1/secret/jenkins/api_token" | jq -r .data.value)}

    HASH=$(echo -n "$JENKINS_PASSWD"'{zil0}' | sha256sum | cut -d' ' -f1)

    echo -e "A default Jenkins user has been created with the credentials:"
    echo -e "login: \e[1madmin\e[0m password: \e[1m$JENKINS_PASSWD"
    echo -e "\e[0mOnce you login, be sure to change the credentials to your needs."

    echo 'writing Jenkins admin user config'
    cat /usr/share/jenkins/templates/users/admin/config.xml | \
        sed "s|JENKINS_API_TOKEN|${JENKINS_API_TOKEN}|" | \
        sed "s|JENKINS_PASSWORD_HASH|${HASH}|" \
            > ${JENKINS_HOME}/users/admin/config.xml

    # make Jenkins password available to our reload-jobs.sh job
    echo 'writing Jenkins admin user .netrc'
    echo "machine localhost" > ${JENKINS_HOME}/.netrc
    echo "login admin" >> ${JENKINS_HOME}/.netrc
    echo "password ${JENKINS_PASSWD}" >> ${JENKINS_HOME}/.netrc
    chmod 600 ${JENKINS_HOME}/.netrc

}

setup_jenkins_ssh() {
    echo 'setting up Jenkins SSHD to listen on port 22'
    cp /usr/share/jenkins/templates/org.jenkinsci.main.modules.sshd.SSHD.xml ${JENKINS_HOME}
}


# write the Triton account ID to the Docker plugin config in config.xml
setup_triton_jenkins_config() {
    if [ -z ${TRITON_ACCOUNT} ]; then
        echo 'TRITON_ACCOUNT not set. Exiting.'
        exit 1
    fi
    if [ -f ${JENKINS_HOME}/config.xml ]; then
        echo 'Jenkins ~/config.xml already configured'
        return
    fi
    echo "writing Triton account info to Jenkins ~/config.xml"
    cat /usr/share/jenkins/templates/config.xml | \
        sed "s/TRITON_ACCOUNT/${TRITON_ACCOUNT}/g" | \
            > ${JENKINS_HOME}/config.xml
}



# uses the PRIVATE_KEY, SDC_URL, and SDC_ACCOUNT variables to point the Docker
# client to the Triton DC
setup_triton_docker_config() {
    if [ -f ${JENKINS_HOME}/.ssh/triton ]; then
        echo 'Triton credentials already configured'
        return
    fi
    echo 'setting up Triton credentials for launching Docker containers'
    mkdir -p ${JENKINS_HOME}/.ssh
    if [ -z ${PRIVATE_KEY} ]; then
        curl -sL \
             --cacert /usr/local/share/ca-certificates/ca_cert.pem \
             -H "X-Vault-Token: ${jenkinsToken}" \
             "https://vault:8200/v1/secret/jenkins/triton_cert" | \
            jq -r .data.value | tr "\\n" "\n" > ${JENKINS_HOME}/.ssh/triton
    else
        echo ${PRIVATE_KEY} | sed 's/#/\n/g' > ${JENKINS_HOME}/.ssh/triton
    fi

    chmod 400 ${JENKINS_HOME}/.ssh/triton
    ssh-keygen -y -f ${JENKINS_HOME}/.ssh/triton -N '' \
               > ${JENKINS_HOME}/.ssh/triton.pub

    echo 'running Triton setup script using your credentials...'
    bash /usr/local/bin/sdc-docker-setup.sh ${SDC_URL} ${SDC_ACCOUNT} ~/.ssh/triton
}

# adds GitHub credentials to the Jenkins plugins
setup_github_credentials() {
    echo "fetching GitHub credentials from Vault"
    GITHUB_API_TOKEN=${GITHUB_API_TOKEN:-$(curl -sL --fail \
         --cacert /usr/local/share/ca-certificates/ca_cert.pem \
         -H "X-Vault-Token: ${jenkinsToken}" \
         "https://vault:8200/v1/secret/jenkins/github_api_token" | jq -r .data.value)}
    GITHUB_HOOK_TOKEN=${GITHUB_HOOK_TOKEN:-$(curl -sL --fail \
         --cacert /usr/local/share/ca-certificates/ca_cert.pem \
         -H "X-Vault-Token: ${jenkinsToken}" \
         "https://vault:8200/v1/secret/jenkins/github_hook_token" | jq -r .data.value)}

    echo "writing GitHub credentials to credentials.xml"
    cat /usr/share/jenkins/templates/credentials.xml | \
        sed "s/GITHUB_API_TOKEN/${GITHUB_API_TOKEN}/" | \
        sed "s/GITHUB_HOOK_TOKEN/${GITHUB_HOOK_TOKEN}/" \
            > ${JENKINS_HOME}/credentials.xml
}


# Copy files from /usr/share/jenkins/ref into ${JENKINS_HOME}
# So the initial JENKINS_HOME is set with expected content.
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
    if [[ ! -e ${JENKINS_HOME}/${rel} || $f = *.override ]]
    then
        echo "copy $rel to JENKINS_HOME" >> "$COPY_REFERENCE_FILE_LOG"
        mkdir -p "${JENKINS_HOME}/${dir:23}"
        cp -r "${f}" "${JENKINS_HOME}/${rel}";
        # pin plugins on initial copy
        [[ ${rel} == plugins/*.jpi ]] && touch "${JENKINS_HOME}/${rel}.pinned"
    fi;
}

setup_deploy_keys() {
    echo 'getting deploy credentials for cloning private GitHub repos'
    mkdir -p ${JENKINS_HOME}/.ssh

    # trust GitHub key
    ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

    # we need to use the credential names saved in credentials.xml to fetch
    # the ssh keys from vault. We use the convention that the description
    # is the name of the key in vault and write out the value to the place
    # expected by the credentials.xml

    local keynames_cfg=$(xmlstarlet sel -t -v '//com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey/description' /usr/share/jenkins/templates/credentials.xml)
    keynames=()
    while read -r line; do
        keynames+=("${line}")
    done <<< "${keynames_cfg}"

    local keyfiles_cfg=$(xmlstarlet sel -t -v '//com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey/privateKeySource/privateKeyFile' /usr/share/jenkins/templates/credentials.xml)
    keyfiles=()
    while read -r line; do
        keyfiles+=("${line}")
    done <<< "${keyfiles_cfg}"

    max=${#keynames[*]}
    for (( i=0; i<$(( $max -1 )); i++))
    do
        local vault_key=${keynames[i]}
        local keyfile=${keyfiles[i]}

        echo "fetching ssh key for ${vault_key}"
        curl -sL \
             --cacert /usr/local/share/ca-certificates/ca_cert.pem \
             -H "X-Vault-Token: ${jenkinsToken}" \
             "https://vault:8200/v1/secret/jenkins/${vault_key}" | \
            jq -r .data.value | tr "\\n" "\n" > "${keyfile}"

        chmod 400 "${keyfile}"
        ssh-keygen -y -f "${keyfile}" -N '' \
                   > "${keyfile}".pub
        echo "wrote ${keyfile}"
    done
}

setup_bootstrap_job() {
    echo 'creating bootstrapping Jenkins job'
    mkdir -p ${JENKINS_HOME}/jobs/jenkins-jobs

    cat /usr/share/jenkins/templates/jenkins-jobs.config.xml | \
        sed "s|GITHUB_JOBS_REPO|${GITHUB_JOBS_REPO}|" | \
        sed "s|GITHUB_JOBS_SPEC|${GITHUB_JOBS_SPEC:-'*/master'}|" \
            > ${JENKINS_HOME}/jobs/jenkins-jobs/config.xml

    curl -XPOST -s --fail -o /dev/null \
         -d @${JENKINS_HOME}/jobs/jenkins-jobs/config.xml \
         --netrc-file /var/jenkins_home/.netrc \
         -H 'Content-Type: application/xml' \
         http://localhost:8000/job/jenkins-jobs/config.xml
}


# ---------------------------------------------------
# parse arguments

cmd=$1
shift
if [ -z $cmd ]; then

    # this setup shouldn't run again if we're just restarting the container
    if [ -f "${JENKINS_HOME}/first-started.txt" ]; then
        echo 'Jenkins has already been setup'
        exit 0
    fi
    date > ${JENKINS_HOME}/first-started.txt

    if [ -z ${VAULT} ]; then
        login_vault_jenkins
        login_vault_jobs
    fi

    setup_jenkins_user
    setup_jenkins_ssh
    setup_triton_jenkins_config
    setup_triton_docker_config
    setup_github_credentials
    setup_jenkins_home
    setup_deploy_keys
    setup_bootstrap_job

    # verify we're good-to-go
    docker info
    exit
fi

echo "[DEBUG] running ${cmd} only"
$cmd $@
