#!/bin/bash

# Usage: ./generate_secrets_docker.sh
# This script will build a docker image that runs the generate_secrets.sh script
# to generate SSL certficates.

if podman -v || (docker -v | grep -q 'podman'); then
  USERNS="--userns=keep-id"
  DOCKER="podman"
elif docker -v; then
  USERNS=""
  DOCKER="docker"
else
  echo "Neither docker nor podman was found."
  exit 1
fi

$DOCKER build --tag domrad/generate-secrets -f dockerfiles/generate_secrets.Dockerfile \
    --build-arg "UID=$(id -u)" --build-arg "GID=$(id -g)" .
mkdir -p secrets
$DOCKER run $USERNS --rm -v "$PWD/secrets:/pipeline-all-in-one/secrets" domrad/generate-secrets
$DOCKER image rm domrad/generate-secrets
