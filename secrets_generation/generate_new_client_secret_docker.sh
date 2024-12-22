#!/bin/bash

# Usage: ./generate_new_client_secret_docker.sh
# This script will build a docker image that runs the generate_new_client_secret.sh script
# to generate a SSL certficate for a new client.

if podman -v >/dev/null 2>&1 || (docker -v 2>/dev/null | grep -q 'podman'); then
  USERNS="--userns=keep-id"
  DOCKER="podman"
elif docker -v >/dev/null 2>&1; then
  USERNS=""
  DOCKER="docker"
else
  echo "Neither docker nor podman was found."
  exit 1
fi

if [[ ! -d "secrets" || ! -d "secrets/ca" ]]; then
  echo "The secrets have not been created yet. Use generate_secrets.sh"
  exit 1
fi

$DOCKER build --tag domrad/generate-secrets -f generate_secrets.Dockerfile \
    --build-arg "UID=$(id -u)" --build-arg "GID=$(id -g)" .
$DOCKER run $USERNS --rm -v "$PWD/secrets:/app/secrets" --entrypoint /bin/bash domrad/generate-secrets ./generate_new_client_secret.sh "$@"
$DOCKER image rm domrad/generate-secrets