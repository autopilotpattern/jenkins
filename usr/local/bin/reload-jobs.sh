#!/bin/bash
# create and update all jobs
# TODO: we probably want a dedicated user for this rather than admin
set -e

for job in ${WORKSPACE}/jobs/*; do

    jobname=$(basename ${job})
    config=${JENKINS_HOME}/jobs/${jobname}/config.xml

    # create a new job for each directory under workspace/jobs
    curl -XPOST -s -o /dev/null \
         -d @${config} \
         --user admin:${JENKINS_PASSWD} \
         -H 'Content-Type: application/xml' \
         http://127.0.0.1/createItem?name=${jobname}

    # update jobs; this re-updates a brand new job but saves us the
    # trouble of parsing Jenkins output and is idempotent for a new
    # job anyways
    curl -XPOST -s -fail -o /dev/null \
         -d @${config} \
         --user admin:${JENKINS_PASSWD} \
         -H 'Content-Type: application/xml' \
         http://127.0.0.1/job/${jobname}/config.xml
done
