#!/bin/bash
# create and update all jobs
set -e

reload() {

    # the job-reloading-job needs to update itself, but note that changes
    # won't be picked up in this pass because we're already running the
    # job. kick the build off manually if you need it immediately, otherwise
    # wait until the next pass
    # TODO: probably want this to kick the job off again but only if there
    # was a change, which means figuring out how to know there was a change
    xmlstarlet \
        ed \
        -u '//project/scm/userRemoteConfigs/hudson.plugins.git.UserRemoteConfig/url' \
        -v ${GITHUB_JOBS_REPO} \
        -u '//project/scm/branches/hudson.plugins.git.BranchSpec/name' \
        -v ${GITHUB_JOBS_SPEC:-'*/master'} \
        /usr/share/jenkins/templates/jenkins-jobs.config.xml \
        > ${JENKINS_HOME}/jobs/jenkins-jobs/config.xml

    for job in ${WORKSPACE}/jenkins/jobs/*; do

        local jobname=$(basename ${job})
        local config=${WORKSPACE}/jenkins/jobs/${jobname}/config.xml

        # create a new job for each directory under workspace/jobs
        curl -XPOST -s -o /dev/null \
             -d @${config} \
             --netrc-file /var/jenkins_home/.netrc \
             -H 'Content-Type: application/xml' \
             http://localhost:8000/createItem?name=${jobname}

        # update jobs; this re-updates a brand new job but saves us the
        # trouble of parsing Jenkins output and is idempotent for a new
        # job anyways
        curl -XPOST -s --fail -o /dev/null \
             -d @${config} \
             --netrc-file /var/jenkins_home/.netrc \
             -H 'Content-Type: application/xml' \
             http://localhost:8000/job/${jobname}/config.xml
    done
}

check() {
    # make sure the first job has run at least once so that
    # we've pulled jobs down from GitHub
    if [ ! -f ${JENKINS_HOME}/jobs/jenkins-jobs/nextBuildNumber ]; then
        curl -XPOST -s --fail -o /dev/null \
             --netrc-file /var/jenkins_home/.netrc \
             http://localhost:8000/job/jenkins-jobs/build
    fi

    # health check
    curl --fail -s -o /dev/null http://localhost:8000/
}


# ---------------------------------------------------
# parse arguments

while true; do
    case $1 in
        check | reload) cmd=$1; shift; break;;
        *) break;;
    esac
done

if [ -z $cmd ]; then
    reload
    exit
fi

$cmd $@
