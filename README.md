# Autopilot Pattern Jenkins

This repo is an extension of the official [Jenkins](https://jenkins.io/) Docker image, designed to be self-operating according to the [autopilot pattern](http://autopilotpattern.io/). This application demonstrates support for building containers via [Joyent's Triton](https://www.joyent.com/) and for provisioning Jenkins slaves via Triton.

[![](https://badge.imagelayers.io/autopilotpattern/jenkins:latest.svg)](https://imagelayers.io/?images=autopilotpattern/jenkins:latest 'Get your own badge on imagelayers.io')
[![DockerPulls](https://img.shields.io/docker/pulls/autopilotpattern/jenkins.svg)](https://registry.hub.docker.com/u/autopilotpattern/jenkins/)
[![DockerStars](https://img.shields.io/docker/stars/autopilotpattern/jenkins.svg)](https://registry.hub.docker.com/u/autopilotpattern/jenkins/)
[![Join the chat at https://gitter.im/autopilotpattern/general](https://badges.gitter.im/autopilotpattern/general.svg)](https://gitter.im/autopilotpattern/general)

### Design

One of the most important aspects of CI is ensuring that the CI system itself is secured, but including credentials to the build system in the container image leaves us open to accidental disclosure. This architecture injects credentials via environment variables and then uses a Containerbuddy `onStart` handler to update the appropriate files required by Jenkins.

Another design constraint is that CI systems often become "pets not cattle," which results in disruption to deployments if the Jenkins server is broken. We can take advantage of the autopilot pattern to have a Jenkins instance bootstrap its job configuration from GitHub during the `onStart` handler.

The `first-run.sh` script called by the `onStart` handler will create a new job called "jenkins-jobs." When triggered, this job pulls a workspace from a git repository passed in the `GITHUB_JOBS_REPO` environment variable and from that repo creates new jobs from each configuration it can find in the workspace's `jobs/` directory. Existing jobs will be updated from the remote repo.


### Caveats

Jenkins requires SSL to be operated securely. You should only run Jenkins behind a reverse proxy that supports SSL (ex. Nginx). If you are running Jenkins in a private network, you'll want to replace the following section of the job-building job found at `usr/share/jenkins/templates/jenkins-jobs.config.xml` in this repo.

```xml
<triggers>
  <com.cloudbees.jenkins.GitHubPushTrigger plugin="github@1.18.1">
    <spec></spec>
  </com.cloudbees.jenkins.GitHubPushTrigger>
</triggers>
```

This configures the job-building job to receive [GitHub webhooks](https://developer.github.com/webhooks/) to fire off the job when the remote repository receives a push. Jenkins will verify the hook is legitimate by sending a request back to GitHub, but this communication should be over SSL in both directions. If your environment cannot support this, you may want to poll the git repository for changes instead:


```xml
<triggers>
  <hudson.triggers.SCMTrigger>
    <spec>H/15 * * * *</spec>
    <ignorePostCommitHooks>false</ignorePostCommitHooks>
  </hudson.triggers.SCMTrigger>
</triggers>
```

This configuration polls the repository every 15 minutes.

### Run it!

1. [Get a Joyent account](https://my.joyent.com/landing/signup/) and [add your SSH key](https://docs.joyent.com/public-cloud/getting-started).
1. Install the [Docker Toolbox](https://docs.docker.com/installation/mac/) (including `docker` and `docker-compose`) on your laptop or other environment, as well as the [Joyent Triton CLI](https://www.joyent.com/blog/introducing-the-triton-command-line-tool) (`triton` replaces our old `sdc-*` CLI tools)
1. [Configure Docker and Docker Compose for use with Joyent](https://docs.joyent.com/public-cloud/api-access/docker):

```bash
curl -O https://raw.githubusercontent.com/joyent/sdc-docker/master/tools/sdc-docker-setup.sh && chmod +x sdc-docker-setup.sh
./sdc-docker-setup.sh -k us-east-1.api.joyent.com <ACCOUNT> ~/.ssh/<PRIVATE_KEY_FILE>
```

Check that everything is configured correctly by running `./setup.sh`. This will check that your environment is setup correctly and will create an `_env` file that includes the credentials and variables that we'll inject into the Jenkins container. You may wish to edit this file with a password for the Jenkins default admin user.
