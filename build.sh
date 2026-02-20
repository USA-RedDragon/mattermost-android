#!/bin/bash

set -euo pipefail

# renovate: datasource=github-tags depName=mattermost/mattermost-mobile
MATTERMOST_VERSION=v2.37.1
# renovate: datasource=github-tags depName=nvm-sh/nvm
NVM_VERSION=v0.40.4

# Default to debug
TYPE=${1:-debug}

MATTERMOST_DIR=$(mktemp -d)

# Clean up on exit
cleanup() {
    set -x
    rm -rf ${MATTERMOST_DIR}
}

trap cleanup EXIT ERR

if [ -f ${HOME}/.nvm/nvm.sh ]; then
    . ${HOME}/.nvm/nvm.sh
else
    # Install nvm
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash
    . ${HOME}/.nvm/nvm.sh
fi

# Clone the repo
git clone https://github.com/mattermost/mattermost-mobile.git ${MATTERMOST_DIR}

RUNDIR=$(pwd)
cd ${MATTERMOST_DIR}
git fetch --all --tags
git checkout ${MATTERMOST_VERSION}

nvm install `cat .node-version`
nvm use `cat .node-version`

sed -i 's/ && npx solidarity//g' package.json
npm ci

mkdir -p assets/override
cp ${RUNDIR}/override.json assets/override/config.json

# Check if GOOGLE_SERVICES_JSON is set
if [ -n "${GOOGLE_SERVICES_JSON:-}" ]; then
    echo "Using GOOGLE_SERVICES_JSON from the environment"
    echo "${GOOGLE_SERVICES_JSON}" > ${MATTERMOST_DIR}/android/app/google-services.json
elif [ -f "${RUNDIR}/google-services.json" ]; then
    echo "Using google-services.json from the repository"
    cp ${RUNDIR}/google-services.json ${MATTERMOST_DIR}/android/app/google-services.json
fi

# Set BETA_BUILD to true if we are building TYPE=release
if [ "${TYPE}" = "release" ]; then
    BETA_BUILD=false
    BUILD_FOR_RELEASE=true
else
    BETA_BUILD=true
    BUILD_FOR_RELEASE=false
fi

# Build the app
env \
  APP_NAME=Mattermost \
  MAIN_APP_IDENTIFIER=dev.mcswain.mattermost \
  BUILD_FOR_RELEASE=${BUILD_FOR_RELEASE} \
  BETA_BUILD=${BETA_BUILD} \
  REPLACE_ASSETS=true \
  SEPARATE_APKS=false \
  CI= \
  npm run build:android

cd ${RUNDIR}
cp -v ${MATTERMOST_DIR}/*.apk .

if [ -n "${GITHUB_WORKFLOW:-}" ]; then
    cat <<__EOF__ > .buildinfo
MATTERMOST_VERSION=${MATTERMOST_VERSION}
__EOF__
fi
