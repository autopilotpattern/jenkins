#!/bin/bash
# create and update all jobs
# TODO: we probably want a dedicated user for this rather than admin
set -e

reload() {
    for job in ${WORKSPACE}/jobs/*; do

        local jobname=$(basename ${job})
        local config=${WORKSPACE}/jobs/${jobname}/config.xml

        # create a new job for each directory under workspace/jobs
        curl -XPOST -s -o /dev/null \
             -d @${config} \
             --user admin:${JENKINS_PASSWD} \
             -H 'Content-Type: application/xml' \
             http://127.0.0.1/createItem?name=${jobname}

        # update jobs; this re-updates a brand new job but saves us the
        # trouble of parsing Jenkins output and is idempotent for a new
        # job anyways
        curl -XPOST -s --fail -o /dev/null \
             -d @${config} \
             --user admin:${JENKINS_PASSWD} \
             -H 'Content-Type: application/xml' \
             http://localhost/job/${jobname}/config.xml
    done
}

check() {
    # make sure the first job has run at least once so that
    # we've pulled jobs down from GitHub
    local nextBuild=$(cat ${JENKINS_HOME}/jobs/jenkins-jobs/nextBuildNumber)
    if [ ${nextBuild} == "1" ]; then
        curl -XPOST -s --fail -o /dev/null \
             --user admin:${JENKINS_PASSWD} \
             http://localhost/job/jenkins-jobs/build
    fi

    # health check
    curl --fail -s -o /dev/null http://localhost/
}

until
    cmd=$1
    if [ ! -z "$cmd" ]; then
        shift 1
        $cmd "$@"
        if [ $? == 127 ]; then
            help
        fi
        exit
    fi
do
    echo
done

# default behavior
reload
