FROM jenkins:1.642.1

MAINTAINER Elijah Zupancic <elijah@zupancic.name>

# Add dependencies for patched Docker Jenkins plugin
COPY usr/share/jenkins/docker-plugin-deps.txt /usr/share/jenkins/docker-plugin-deps.txt
RUN /usr/local/bin/plugins.sh /usr/share/jenkins/docker-plugin-deps.txt

# Add patched Docker Jenkins plugin
RUN curl --retry 6 -sSL -f https://github.com/dekobon/docker-plugin/releases/download/sdc-patch/docker-plugin.hpi -o /usr/share/jenkins/ref/plugins/docker-plugin.jpi && \
    unzip -qt /usr/share/jenkins/ref/plugins/docker-plugin.jpi && \
    chown -R jenkins:jenkins /usr/share/jenkins/ref/plugins

USER root

# Add authbind so that we can listen on lower ports
RUN apt-get update && \
    apt-get install -y authbind xmlstarlet dc uuid-runtime && \
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

COPY usr/local/bin/jenkins-triton.sh /usr/local/bin/jenkins-triton.sh
COPY usr/local/bin/generate-cert.sh /usr/local/bin/generate-cert.sh
COPY usr/local/bin/proclimit.sh /usr/local/bin/proclimit.sh
COPY usr/share/jenkins/templates /usr/share/jenkins/templates

RUN chmod +x /usr/local/bin/jenkins-triton.sh && \
    chmod +x /usr/local/bin/generate-cert.sh && \
    chmod +x /usr/local/bin/proclimit.sh

USER jenkins

EXPOSE 22
EXPOSE 443

ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/jenkins-triton.sh"]
