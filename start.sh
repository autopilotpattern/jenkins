#!/usr/bin/env bash

docker-compose -p jj run --entrypoint /usr/local/bin/first-run.sh jenkins
docker-compose -p jj up -d
