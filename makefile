MAKEFLAGS += --warn-undefined-variables
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail
.DEFAULT_GOAL := build

TAG?=latest

# run the Docker build
build:
	docker -f local-compose.yml build

# push our image to the public registry
ship:
	docker tag jenkins_jenkins autopilotpattern/jenkins:${TAG}
	docker tag jenkins_jenkins autopilotpattern/jenkins:latest
	docker tag jenkins_nginx autopilotpattern/jenkins-nginx:${TAG}
	docker tag jenkins_nginx autopilotpattern/jenkins-nginx:latest
	docker push "autopilotpattern/jenkins:${TAG}"
	docker push "autopilotpattern/jenkins-nginx:${TAG}"
	docker push "autopilotpattern/jenkins:latest"
	docker push "autopilotpattern/jenkins-nginx:latest"
