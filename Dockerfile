FROM jenkins:1.642.1

MAINTAINER Elijah Zupancic <elijah@zupancic.name>

ENV CONTAINERBUDDY_VER 1.1.0
ENV CONTAINERBUDDY_CHECKSUM 5cb5212707b5a7ffe41ee916add83a554d1dddfa

# Add dependencies for patched Docker Jenkins plugin
COPY usr/share/jenkins/docker-plugin-deps.txt /usr/share/jenkins/docker-plugin-deps.txt
RUN /usr/local/bin/plugins.sh /usr/share/jenkins/docker-plugin-deps.txt

# Add patched Docker Jenkins plugin
RUN curl --retry 6 -sSL -f https://github.com/dekobon/docker-plugin/releases/download/sdc-patch/docker-plugin.hpi -o /usr/share/jenkins/ref/plugins/docker-plugin.jpi && \
    unzip -qt /usr/share/jenkins/ref/plugins/docker-plugin.jpi && \
    chown -R jenkins:jenkins /usr/share/jenkins/ref/plugins

USER root

COPY opt/containerbuddy /opt/containerbuddy

RUN curl --retry 6 -sSL -f https://github.com/joyent/containerbuddy/releases/download/$CONTAINERBUDDY_VER/containerbuddy-$CONTAINERBUDDY_VER.tar.gz -o /tmp/containerbuddy.tar.gz && \
    echo "$CONTAINERBUDDY_CHECKSUM  /tmp/containerbuddy.tar.gz" | sha1sum -c && \
    tar xzf /tmp/containerbuddy.tar.gz -C /opt/containerbuddy && \
    chmod +x /opt/containerbuddy/containerbuddy && \
    chown -R jenkins:jenkins /opt/containerbuddy && \
    rm -f /tmp/containerbuddy.tar.gz

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

COPY usr/local/bin/first-run.sh /usr/local/bin/first-run.sh
COPY usr/local/bin/triton-jenkins.sh /usr/local/bin/triton-jenkins.sh
COPY usr/local/bin/proclimit.sh /usr/local/bin/proclimit.sh
COPY usr/share/jenkins/templates /usr/share/jenkins/templates

RUN chmod +x /usr/local/bin/triton-jenkins.sh && \
    chmod +x /usr/local/bin/first-run.sh && \
    chmod +x /usr/local/bin/proclimit.sh

USER jenkins

EXPOSE 22
EXPOSE 80

ENTRYPOINT ["/opt/containerbuddy/containerbuddy", "-config", "/opt/containerbuddy/app.json"]
