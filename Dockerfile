FROM jenkins:2.19.3

USER root

# Add authbind so that we can listen on lower ports
# Add docker so that we can provision using the Docker API on Triton
# Add xmlstarlet, dc and uuid-runtime so we can auto-configure Jenkins
RUN apt-get update && \
    apt-get install -y \
        apt-transport-https \
        ca-certificates && \
    apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D && \
    echo 'deb https://apt.dockerproject.org/repo debian-jessie main' > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-cache policy docker-engine && \
    apt-get install -y \
        authbind \
        xmlstarlet \
        dc \
        uuid-runtime \
        docker-engine && \
    rm -rf /var/lib/apt/lists/* && \
    touch /etc/authbind/byport/22 && \
    touch /etc/authbind/byport/80 && \
    touch /etc/authbind/byport/443 && \
    chmod 500 /etc/authbind/byport/22 && \
    chmod 500 /etc/authbind/byport/80 && \
    chmod 500 /etc/authbind/byport/443 && \
    chown jenkins /etc/authbind/byport/22 && \
    chown jenkins /etc/authbind/byport/80 && \
    chown jenkins /etc/authbind/byport/443

# Add SDC setup script
RUN curl --retry 6 -sSL -o /usr/local/bin/sdc-docker-setup.sh \
https://raw.githubusercontent.com/joyent/sdc-docker/master/tools/sdc-docker-setup.sh \
   && chmod +x /usr/local/bin/sdc-docker-setup.sh

# Add ContainerPilot and its configuration
ENV CONTAINERPILOT file:///etc/containerpilot.json

RUN export checksum=b56a9aff365fd9526cd0948325f91a367a3f84a1 \
    && export archive=containerpilot-2.5.1.tar.gz \
    && curl -Lso /tmp/${archive} \
    https://github.com/joyent/containerpilot/releases/download/2.5.1/${archive} \
    && echo "${checksum}  /tmp/${archive}" | sha1sum -c \
    && tar zxf /tmp/${archive} -C /usr/local/bin \
    && rm /tmp/${archive}

COPY etc/containerpilot.json /etc/containerpilot.json

# ------------------------------------------------
# install Jenkins plugins and configuration

USER jenkins

# Add Jenkins plugins
RUN /usr/local/bin/install-plugins.sh git github token-macro docker-plugin

# Jenkins config and templates
COPY usr/local/bin/first-run.sh /usr/local/bin/first-run.sh
COPY usr/local/bin/jenkins.sh /usr/local/bin/jenkins.sh
COPY usr/local/bin/proclimit.sh /usr/local/bin/proclimit.sh
COPY usr/local/bin/reload-jobs.sh /usr/local/bin/reload-jobs.sh
COPY usr/share/jenkins/templates /usr/share/jenkins/templates

EXPOSE 22
EXPOSE 8000

ENTRYPOINT []
CMD ["/usr/local/bin/containerpilot", "/usr/local/bin/jenkins.sh"]
