#!/usr/bin/env bash

TEMP_DIR=$(mktemp -d)

openssl genrsa -out ${TEMP_DIR}/key.pem > /dev/null
openssl req -new -key ${TEMP_DIR}/key.pem -out ${TEMP_DIR}/csr.pem \
    -subj "/C=??/ST=Jenkins/L=Jenkinsville" > /dev/null
openssl x509 -req -days 9999 -in ${TEMP_DIR}/csr.pem \
    -signkey ${TEMP_DIR}/key.pem -out ${TEMP_DIR}/cert.pem \
    > /dev/null

echo ${TEMP_DIR}
