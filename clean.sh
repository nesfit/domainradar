#!/usr/bin/env bash

source options.sh

help() {
    cat <<-EOHELP
Usage: $0 d[irs]|s[ources]|i[mages]|a[ll]
  dirs:    removes *all* source directories (incl. infra)
  sources: removes all source code directories (without infra)
  images:  removes built Docker images
  all:     dirs + images
EOHELP
}

remove_sources() {
    rm -rf "$CLF_DIR"
    rm -rf "$COLEXT_DIR"
    rm -rf "$LOADER_DIR"
    rm -rf "$WEBUI_DIR"
}

remove_dirs() {
    remove_sources
    rm -rf "$INFRA_DIR"
    rm -rf "$INFRA_TEMPLATE_DIR"
}

remove_images() {
    $DOCKER image ls | awk '/domrad\// {print $3}' | xargs -r $DOCKER image rm -f
}

case "$1" in
    d|dirs)
        remove_dirs ;;
    s|sources) 
        remove_sources ;;
    i|images) 
        remove_images ;;
    a|all)
        remove_dirs
        remove_images ;;
    *) help ;;
esac

