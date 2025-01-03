#!/usr/bin/env bash

source options.sh

CLEAR_GIT_FILES=$([ "$1" = "--clear-git-files" ] && echo true || echo false)

clone_or_pull() {
    local target_dir="$1"
    local repo="$2"
    local branch="$3"
    local working_dir="$PWD"

    if [ -d "$target_dir" ]; then
        echo "Pulling latest $repo"
        cd "$target_dir" || exit 1

        git fetch --all
        git checkout "$branch"
        git merge --ff-only
        cd "$working_dir"
    else
        echo Cloning "$repo"
        git clone --filter=blob:none -b "$branch" "git@github.com:nesfit/$repo.git" "$target_dir"

        if $CLEAR_GIT_FILES; then
            cd "$target_dir"
            rm -rf ".git"
            cd "$working_dir"
        fi
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