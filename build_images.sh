#!/usr/bin/env bash

source options.sh

working_dir="$PWD"

echo "Building the domrad/loader image"
$DOCKER build -t domrad/loader -f- "$LOADER_DIR" < dockerfiles/prefilter.Dockerfile

echo "Building the domrad/webui image"
cd "$WEBUI_DIR" || exit 1
$DOCKER build -t domrad/webui .
cd "$working_dir"

echo "Building the pipeline images"
cd "$COLEXT_DIR" || exit 1
./build_images.sh
cd "$working_dir"
