# Autopilot Pattern Jenkins

*CI/CD infrastructure for the Autopilot Pattern*

This repo is an extension of the official [Jenkins](https://jenkins.io/) Docker image, designed to be self-operating according to the [Autopilot Pattern](http://autopilotpattern.io/). This application demonstrates support for building containers and deploying to [Joyent's Triton](https://www.joyent.com/).

[![DockerPulls](https://img.shields.io/docker/pulls/autopilotpattern/jenkins.svg)](https://registry.hub.docker.com/u/autopilotpattern/jenkins/)
[![DockerStars](https://img.shields.io/docker/stars/autopilotpattern/jenkins.svg)](https://registry.hub.docker.com/u/autopilotpattern/jenkins/)


## Design

The *Build Machine* is a KVM instance on Triton Cloud running Docker.

*Jenkins* runs in a Docker container on the Build Machine.
- KVM machine's docker.sock mounted from the host inside the container, which allows Jenkins to create containers on its own host.
- Jenkins uses Docker "host" networking to expose its API to the localhost; doesn't bind to the machine's public IP.

*Nginx* runs in front of Jenkins, in a Docker container on the same KVM host. Nginx uses [Let's Encrypt](https://letsencrypt.org/) to get a TLS certificate, using a local *Consul* instance to coordinate the handling of the certificate challenge as demonstrated in [autopilotpattern/nginx](https://github.com/autopilotpattern/nginx).


### Bootstrapping

Setup and run the KVM:
- KVM machine is provisioned via Ansible: Docker installed, Jenkins container built locally from autopilotpattern/jenkins.
- Start KVM machine from that image (via Triton CLI)
- The KVM starts (via systemd) Docker, Consul (as an agent pointing to Vault-Consul), the Jenkins container, the Nginx container, and a local Consul container.
- Nginx uses Let's Encrypt to get a TLS cert for its domain.


### Job Workflow

Once the cluster is bootstrapped, Jenkins jobs that build and test applications can operate as follows:

- Jenkins receives webhooks from GitHub to run a job.
- Jenkins job fetches/updates GitHub repo
- Jenkins job performs any local unit tests, linting, etc.
- Jenkins job builds container images via docker build locally, tagging the images with the commit ID.
- Jenkins job pushes these container images to Docker Hub
- Jenkins job executes tests by running the stack on Triton and performing project-specific testing.
- On success, Jenkins job tags the container images as :latest and pushes the tag to the Docker Hub.


### Job-Building-Jobs

Another design constraint for CI systems is that they often become "pets not cattle," which results in disruption to deployments if the Jenkins server is broken. We can take advantage of ContainerPilot to have a Jenkins instance bootstrap its job configuration from GitHub during the `preStart` handler.

The `first-run.sh` script called by the `preStart` handler will create a new job called "jenkins-jobs". When triggered, this job pulls a workspace from a git repository passed in the `GITHUB_JOBS_REPO` environment variable and from that repo creates new jobs from each configuration it can find in the workspace's `jobs/` directory. Existing jobs will be updated from the remote repo.


## Operations

This repo contains a management script `manage.sh` that can deploy and update the Jenkins KVM instance.

```
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

```

### Deployment

To run the deployment, you'll need the following:

- A properly configured Triton CLI pointed at the target environment
- Ansible deployed on your workstation
- Triton ssh private key stored at `./builder/keys_private/triton`
- GitHub ssh deployment private keys for private GitHub repos stored at `./builder/keys_private/*`
- (Optional) team member ssh public keys stored at `./builder/keys_public/*.pub`
- GitHub API token for your GitHub account, ready to be entered into `./manage.sh setup`
- GitHub web hook token for your GitHub project, ready to be entered into `./manage.sh setup`
- GitHub OAuth application Client Id and Secret, ready to be entered into `./manage.sh setup`

You can ssh into the running Jenkins instance with `triton ssh ubuntu@${jenkins-hostname}`. Once you are logged in, you'll find there's a `jenkins` command that will manipulate Jenkins via systemd and Docker Compose. A checkout of this repo can be found at `/opt/jenkins`.

```
Usage: sudo jenkins <subcommand>

sudo jenkins start: starts Jenkins via systemd and docker-compose
sudo jenkins stop: stops Jenkins but does not remove containers
sudo jenkins kill: stop Jenkins and removes containers

```

### Adding new Jenkins jobs

Use GitHub OAuth to log into the Jenkins UI to add a job normally. You'll probably want to clone an existing job and modify it. When you're done, use the `./manage.sh cp` command to copy the job definition into this repo and commit it.

We want to build containers on the Jenkins instance itself and then push them to a registry for deployment on Triton. An example workflow in a job might look like the following. This could be in the job config itself or (more likely) within a Makefile or shell script in the target repo.

```
# build
export DOCKER_HOST=
export DOCKER_TLS_VERIFY=
docker build -t=myimage:${GIT_COMMIT} .

# push
docker push myimage:${GIT_COMMIT}

# deploy tests
export TRITON_DC=us-sw-1
export DOCKER_HOST=tcp://${TRITON_DC}.docker.joyent.com:2376
export DOCKER_TLS_VERIFY=1
docker-compose up -d
```

Jenkins jobs that are getting code from private GitHub repositories will need to have their keys provisioned to the KVM instance by adding them to the `./builder/keys_private` directory. You'll also need to add the credentials to the `./jenkins/templates/credentials.xml` file in a section like the following:

```
        <com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey plugin="ssh-credentials@1.12">
          <scope>GLOBAL</scope>
          <id>208acc1b-bded-4a54-94b5-b929cc0ff89e</id>
          <description>my-project-name</description>
          <username>git</username>
          <passphrase>wc4qGO8Yr6b9FGI4jhdjBw==</passphrase>
          <privateKeySource class="com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey$FileOnMasterPrivateKeySource">
            <privateKeyFile>/var/jenkins_home/.ssh/my-project-name</privateKeyFile>
          </privateKeySource>
        </com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey>
```
