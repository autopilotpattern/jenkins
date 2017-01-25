#!/bin/bash
set -e -o pipefail

# KVM parameters
name="leeroy-jenkins"
image="ubuntu-certified-16.04"
package="k4-highcpu-kvm-1.75G"

help() {
cat << EOF
Usage: ./manage.sh <command> <subcommand>
--------------------------------------------------------------------------------
manage.sh setup [option]:
	Creates environment files that will be uploaded to the Jenkins instance.
	Options:
	- nginx: sets up the Nginx environment file only
	- jenkins: sets up the Jenkins environment file only

manage.sh up:
	Launches the Jenkins KVM instance.

manage.sh provision:
	Performs an Ansible playbook run on the Jenkins KVM instance.

manage.sh cp <Jenkins path> <local path>:
	Copies a file or directory from the Jenkins container so we can commit
	them to GitHub without giving Jenkins push access to its own code
	repository.

EOF

}

# prints the argument bold and then resets the terminal colors
bold() {
    echo "$(tput bold)${1}$(tput sgr0)"
}


# ---------------------------------------------------
# 'setup' top-level command

setup() {
    check
    while true; do
        case $1 in
            jenkins) _jenkins_env; exit;;
            nginx) _nginx_env; exit;;
            *) break;;
        esac
    done
    _jenkins_env
    _nginx_env
}

gentoken() {
    local length=$1
    local token
    token=$(dd if=/dev/urandom bs="${length}" count=1 2> /dev/null | base64 | tr -d "\n")
    echo "${token}"
}

# Check for correct local configuration
check() {
    local docker_user docker_dc triton_cns_enabled
    command -v docker >/dev/null 2>&1 || {
        echo
        bold 'Docker is required, but does not appear to be installed.'
        echo 'See https://docs.joyent.com/public-cloud/api-access/docker'
        exit 1
    }
    command -v triton >/dev/null 2>&1 || {
        echo
        bold 'Error! Joyent Triton CLI is required, but does not appear to be installed.'
        echo 'See https://www.joyent.com/blog/introducing-the-triton-command-line-tool'
        exit 1
    }
    command -v ansible-playbook >/dev/null 2>&1 || {
        echo
        bold 'Error! Ansible is required, but does not appear to be installed.'
        exit 1
    }
    # make sure Docker client is pointed to the same place as the Triton client
    docker_user=$(docker info 2>&1 | awk -F": " '/SDCAccount:/{print $2}')
    docker_dc=$(echo "$DOCKER_HOST" | awk -F"/" '{print $3}' | awk -F'.' '{print $1}')
    TRITON_USER=$(triton profile get | awk -F": " '/account:/{print $2}')
    TRITON_DC=$(triton profile get | awk -F"/" '/url:/{print $3}' | awk -F'.' '{print $1}')
    TRITON_ACCOUNT=$(triton account get | awk -F": " '/id:/{print $2}')
    if [ ! "$docker_user" = "$TRITON_USER" ] || [ ! "$docker_dc" = "$TRITON_DC" ]; then
        echo
        bold 'Error! The Triton CLI configuration does not match the Docker CLI configuration.'
        echo
        echo "Docker user: ${docker_user}"
        echo "Triton user: ${TRITON_USER}"
        echo "Docker data center: ${docker_dc}"
        echo "Triton data center: ${TRITON_DC}"
        exit 1
    fi
    triton_cns_enabled=$(triton account get | awk -F": " '/cns/{print $2}')
    if [ ! "true" == "$triton_cns_enabled" ]; then
        echo
        bold 'Error! Triton CNS is required and not enabled.'
        exit 1
    fi
}

# writes an environment file that will be used for Jenkins; this will include
# your current Triton configuration
_jenkins_env() {
    if [ -f builder/_jenkins ]; then
        echo 'Jenkins environment already configured.'
        return
    fi
    echo
    bold '* Configuring Triton environment for Jenkins'
    TRITON_ACCOUNT=${TRITON_ACCOUNT:-$(triton account get | awk -F": " '/id:/{print $2}')}
    TRITON_DC=${TRITON_DC:-$(triton profile get | awk -F"/" '/url:/{print $3}' | awk -F'.' '{print $1}')}
    {
        echo '# Triton configuration'
        echo "SDC_URL=${SDC_URL}"
        echo "SDC_ACCOUNT=${SDC_ACCOUNT}"
        echo "TRITON_ACCOUNT=${TRITON_ACCOUNT}"
        echo "TRITON_DC=${TRITON_DC}"
        echo "DOCKER_CERT_PATH=/var/jenkins_home/.sdc/docker/${TRITON_ACCOUNT}"
        echo "DOCKER_HOST=tcp://${TRITON_DC}.docker.joyent.com:2376"
    } > builder/_jenkins

    echo
    bold '* Configuring GitHub environment'
    echo -n "Provide GitHub API user [or hit Enter to skip for now]: "
    read -r githubUser
    echo -n "Provide GitHub API token [or hit Enter to skip for now]: "
    read -r githubApiToken
    echo -n "Provide GitHub hook token [or hit Enter to autogenerate]: "
    read -r githubHookToken
    echo -n "Provide GitHub OAuth Client ID [or hit Enter to skip for now]: "
    read -r githubOAuthClientId
    echo -n "Provide GitHub API token [or hit Enter to skip for now]: "
    read -r githubOAuthSecret
    echo -n "Provide path to jobs directory in GitHub repo [or hit Enter to default to jenkins/jobs]: "
    read -r jenkinsJobsPath

    githubHookToken=${githubHookToken:-$(gentoken 20)}
    {
        echo
        echo '# GitHub config'
        echo 'GITHUB_JOBS_REPO=git@github.com:autopilotpattern/jenkins.git'
        echo 'GITHUB_JOBS_SPEC='
        echo "GITHUB_USER=${githubUser}"
        echo "GITHUB_API_TOKEN=${githubApiToken}"
        echo "GITHUB_HOOK_TOKEN=${githubHookToken}"
        echo "GITHUB_OAUTH_CLIENT_ID=${githubOAuthClientId}"
        echo "GITHUB_OAUTH_SECRET=${githubOAuthSecret}"
        echo "JENKINS_JOBS_PATH=${jenkinsJobsPath:-jenkins/jobs}"
    } >> builder/_jenkins

    echo
    bold '* Configuring Jenkins environment'
    echo -n "Provide Jenkins password [or hit Enter to autogenerate]: "
    read -r jenkinsPassword
    echo -n "Provide Jenkins API token [or hit Enter to autogenerate]: "
    read -r jenkinsApiToken
    jenkinsPassword=${jenkinsPassword:-$(gentoken 9)}
    jenkinsApiToken=${jenkinsApiToken:-$(gentoken 64)}
    {
        echo
        echo '# Jenkins config'
        echo "JENKINS_PASSWD=${jenkinsPassword}"
        echo "JENKINS_API_TOKEN=${jenkinsApiToken}"
    } >> builder/_jenkins

    echo
    bold '* Check the results in builder/_jenkins for Jenkins'
}

_nginx_env() {
    if [ -f builder/_nginx ]; then
        echo 'Nginx environment already configured.'
        return
    fi

    echo
    bold "* Configuring Nginx Let's Encrypt environment"
    echo -n "Provide ACME domain [or hit Enter to skip for now]: "
    read -r acmeDomain
    echo -n "Provide ACME environment [or hit Enter to default to staging]: "
    read -r acmeEnv
    {
        echo '# Nginx domain configuration'
        echo "ACME_DOMAIN=${acmeDomain}"
        echo "ACME_ENV=${acmeEnv:-staging}"
    } > builder/_nginx
    echo
    bold '* Check the results in builder/_nginx for Nginx'
}

# ---------------------------------------------------
# Jenkins top-level commands


# creates the Build Machine KVM instance ("Leeroy Jenkins")
_jenkins_create() {
    local private public id
    private=$(triton network ls -l | awk -F' +' '/default/{print $1}')
    public=$(triton network ls -l | awk -F' +' '/Joyent-SDC-Public/{print $1}')
    triton instance create \
           --name="${name}" "${image}" "${package}" \
           --network="${public},${private}" \
           --tag="triton.cns.services=product-ci" \
           --tag="sdc_docker=true" \
           --script=./builder/userscript.sh

    # firewall the instance
    id=$(triton ls -l | awk '/leeroy-jenkins/{print $1}')
    triton fwrule create "FROM any TO vm ${id} ALLOW tcp PORT 22"
    triton fwrule create "FROM any TO vm ${id} ALLOW tcp PORT 443"
    triton fwrule create "FROM any TO vm ${id} ALLOW tcp PORT 80"
    triton fwrule create "FROM any TO vm ${id} BLOCK tcp PORT ALL"
    triton fwrule create "FROM any TO vm ${id} BLOCK udp PORT ALL"

    echo -n 'waiting for Jenkins to enter running state...'
    while true; do
        state=$(triton ls -l | awk '/leeroy-jenkins/{print $6}')
        if [  "${state}" == 'running' ]; then
            break
        fi
        echo -n '.'
        sleep 3
    done
    echo ' running!'
    triton inst enable-firewall "${id}"
}


_jenkins_provision() {
    _jenkins_inventory
    cd builder && ansible-playbook -v -i ./inventory ./vm.yml
}

_jenkins_inventory() {
    echo '[builder]' > builder/inventory
    triton ip "${name}" >> builder/inventory
}

# pull down Jenkins config changes so they can be committed locally here
_jenkins_cp() {
    remote="${1}"
    local="${2}"
    if [ -z "${remote}" ]; then
        echo "Must provide a remote path"
        exit 1
    fi
    if [ -z "${local}" ]; then
        echo "Must provide a local path."
        exit 1
        fi
    ip=$(triton ip leeroy-jenkins)
    base=$(basename "${remote}")
    ssh ubuntu@"${ip}" docker cp "jenkins_jenkins_1:${remote}" /home/ubuntu/
    scp -r "ubuntu@${ip}:/home/ubuntu/${base}" "./${base}"
}

# ---------------------------------------------------
# parse arguments

while true; do
    case $1 in
        setup | help) cmd=$1; break;;
        start | up | run ) cmd=_jenkins_create; break;;
        provision | update) cmd=_jenkins_provision; break;;
        cp) cmd=_jenkins_cp; break;;
        *) break;;
    esac
done

if [ -z "${cmd}" ]; then
    help
    exit
fi

shift
$cmd "${@}"
