FROM docker.io/eclipse-temurin:21-jre
ARG UID
ARG GID

WORKDIR /app

COPY generate_secrets.sh .
COPY generate_new_client_secret.sh .
COPY openssl-ca.cnf .

RUN touch /.rnd && chown ${UID}:${GID} /.rnd
USER ${UID}:${GID}
ENV RANDFILE=/.rnd

ENTRYPOINT [ "bash", "./generate_secrets.sh" ]
