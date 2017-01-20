# Nginx container for securing access to Jenkins
FROM autopilotpattern/nginx:latest

ENV CONSUL 127.0.0.1
COPY containerpilot.json /etc/containerpilot.json
COPY nginx.conf.ctmpl /etc/nginx/nginx.conf.ctmpl
