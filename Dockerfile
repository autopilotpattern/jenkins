FROM jenkins:1.642.2

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

# Add Containerbuddy and its configuration
ENV CONTAINERBUDDY_VER 1.2.1
ENV CONTAINERBUDDY_CHECKSUM aca04b3c6d6ed66294241211237012a23f8b4f20
ENV CONTAINERBUDDY file:///etc/containerbuddy.json

RUN export CB_SHA1=aca04b3c6d6ed66294241211237012a23f8b4f20 \
    && curl -Lso /tmp/containerbuddy.tar.gz \
         "https://github.com/joyent/containerbuddy/releases/download/${CONTAINERBUDDY_VER}/containerbuddy-${CONTAINERBUDDY_VER}.tar.gz" \
    && echo "${CONTAINERBUDDY_CHECKSUM}  /tmp/containerbuddy.tar.gz" | sha1sum -c \
    && tar zxf /tmp/containerbuddy.tar.gz -C /bin \
    && rm /tmp/containerbuddy.tar.gz

COPY etc/containerbuddy.json etc/containerbuddy.json


# ------------------------------------------------
# install Jenkins plugins and configuration

USER jenkins

# Add Jenkins plugins
COPY usr/share/jenkins/plugin-deps.txt /usr/share/jenkins/plugin-deps.txt
RUN /usr/local/bin/plugins.sh /usr/share/jenkins/plugin-deps.txt

# Add patched Docker Jenkins plugin
RUN curl --retry 6 -sSL -f https://github.com/dekobon/docker-plugin/releases/download/sdc-patch/docker-plugin.hpi -o /usr/share/jenkins/ref/plugins/docker-plugin.jpi && \
    unzip -qt /usr/share/jenkins/ref/plugins/docker-plugin.jpi && \
    chown -R jenkins:jenkins /usr/share/jenkins/ref/plugins

# Jenkins config and templates
COPY usr/local/bin/first-run.sh /usr/local/bin/first-run.sh
COPY usr/local/bin/jenkins.sh /usr/local/bin/jenkins.sh
COPY usr/local/bin/proclimit.sh /usr/local/bin/proclimit.sh
COPY usr/local/bin/reload-jobs.sh /usr/local/bin/reload-jobs.sh
COPY usr/share/jenkins/templates /usr/share/jenkins/templates

EXPOSE 22
EXPOSE 80

ENTRYPOINT []
CMD ["/bin/containerbuddy", "/usr/local/bin/jenkins.sh"]
