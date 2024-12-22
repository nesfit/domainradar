#!/usr/bin/env bash

source options.sh

clone_or_pull() {
  if [ -d "$1" ]; then
    echo "Pulling latest $2"
    cd "$1" || exit 1

    git fetch --all
    git checkout "$3"
    git merge --ff-only
    cd ..
  else
    echo Cloning "$2"
    git clone --filter=blob:none -b "$3" "git@github.com:nesfit/$2.git" "$1"
  fi
}

check_git_lfs() {
    # Check if Git LFS is installed
    if ! command -v git-lfs >/dev/null 2>&1; then
        return 1
    fi

    # Check if Git LFS is initialized
    if ! git lfs env >/dev/null 2>&1; then
        echo "Git LFS is installed but not initialized. Initializing..."
        git lfs install

        if [ $? -eq 0 ]; then
            echo "Git LFS initialized successfully."
            return 0
        else
            echo "Failed to initialize Git LFS."
            return 1
        fi
    fi

    return 0
}

clone_or_pull "$INFRA_DIR"  "domainradar-infra"  "$INFRA_BRANCH"
clone_or_pull "$COLEXT_DIR" "domainradar-colext" "$COLEXT_BRANCH"
clone_or_pull "$LOADER_DIR" "domainradar-input"  "$LOADER_BRANCH"
clone_or_pull "$WEBUI_DIR"  "domainradar-ui"     "$WEBUI_BRANCH"

if check_git_lfs; then
    clone_or_pull "$CLF_DIR" "domainradar-clf"   "$CLF_BRANCH"
else
    echo "Git LFS is not installed, cannot pull the classifiers."
fi