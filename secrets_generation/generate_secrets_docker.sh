#!/bin/bash

# Usage: ./generate_secrets_docker.sh
# This script will build a docker image that runs the generate_secrets.sh script
# to generate SSL certficates.

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

if [[ -d "secrets" && -d "secrets/ca" ]]; then
  echo "The secrets have already been created."
  echo "You can use generate_new_client_secret.sh to add another client."
  exit 1
fi

mkdir -p secrets

$DOCKER build --tag domrad/generate-secrets -f generate_secrets.Dockerfile \
    --build-arg "UID=$(id -u)" --build-arg "GID=$(id -g)" .
$DOCKER run $USERNS --rm -v "$PWD/secrets:/app/secrets" domrad/generate-secrets
$DOCKER image rm  --force domrad/generate-secrets
