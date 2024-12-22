INFRA_DIR="./infra"
INFRA_TEMPLATE_DIR="./_infra-template"
LOADER_DIR="./input"
COLEXT_DIR="./colext"
WEBUI_DIR="./ui"
CLF_DIR="./colext/python_pipeline/domainradar-clf"

INFRA_BRANCH="rework"
LOADER_BRANCH="main"
COLEXT_BRANCH="main"
WEBUI_BRANCH="main"
CLF_BRANCH="main"

if podman -v >/dev/null 2>&1 || (docker -v 2>/dev/null | grep -q 'podman'); then
  DOCKER="podman"
elif docker -v >/dev/null 2>&1; then
  DOCKER="docker"
else
  echo "Warning: docker/podman not found"
fi
