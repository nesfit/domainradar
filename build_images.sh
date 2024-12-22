#!/usr/bin/env bash

source options.sh

echo "Building the domrad/loader image"
$DOCKER build -t domrad/loader -f dockerfiles/prefilter.Dockerfile .

echo "Building the domrad/webui image"
cd "$WEBUI_DIR" || exit 1
$DOCKER build -t domrad/webui .
cd ..

echo "Building the pipeline images"
cd "$COLEXT_DIR" || exit 1
./build_images.sh
cd ..
