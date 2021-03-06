
#!/usr/bin/env bash -e
VERSION=$1
ACCESS_TOKEN=$2
DOCKER_USER=$3
DOCKER_PWD=$4
FROM_DOCKERHUB_NAMESPACE=${5:-vschinaiot}
TO_DOCKERHUB_NAMESPACE=${6:-vschinaiot}
SOURCE_TAG="${7:-testing}"
DESCRIPTION=$8
PRE_RELEASE=${9:-false}
LOCAL=${10}
APP_HOME="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && cd .. && pwd )/"

NC="\033[0m" # no color
CYAN="\033[1;36m" # light cyan
YELLOW="\033[1;33m" # yellow
RED="\033[1;31m" # light red

failed() {
    SUB_MODULE=$1
    echo -e "${RED}Cannot find directory $SUB_MODULE${NC}"
    exit 1
}

usage() {
    echo -e "${RED}ERROR: $1 is a required parameter${NC}"
    echo "Usage:"
    echo -e "./release version access_token docker_user docker_pwd from_dockerhub(default:vschinaiot) to_dockerhub(default:vschinaiot) source_tag(default:testing) description(default:empty) pre_release(default:false)"
}

check_input() {
    if [ ! -n "$VERSION" ]; then
        usage "version"
    fi
    if [ ! -n "$ACCESS_TOKEN" ]; then
        usage "access_token"
    fi
    if [ ! -n "$DOCKER_USER" ]; then
        usage "docker_user"
    fi
    if [ ! -n "$DOCKER_PWD" ]; then
        usage "docker_pwd"
    fi
    exit 1
    echo $DOCKER_PWD | docker login -u $DOCKER_USER --password-stdin
}

tag_build_publish_repo() {
    SUB_MODULE=$1
    REPO_NAME=$2
    DOCKER_CONTAINER_NAME=${3:-$2}
    DESCRIPTION=$4

    echo
    echo -e "${CYAN}====================================     Start: Tagging the $REPO_NAME repo     ====================================${NC}"
    echo
    echo -e "Current working directory ${CYAN}$APP_HOME$SUB_MODULE${NC}"
    echo
    cd $APP_HOME$SUB_MODULE || failed $SUB_MODULE

    if [ -n "$LOCAL" ]; then
        echo "Cleaning the repo"
        git reset --hard origin/master
        git clean -xdf
    fi
    git checkout master
    git pull --all --prune
    git fetch --tags

    git tag --force $VERSION
    git push https://$ACCESS_TOKEN@github.com/Azure/$REPO_NAME.git $VERSION

    echo
    echo -e "${CYAN}====================================     End: Tagging $REPO_NAME repo     ====================================${NC}"
    echo

    echo
    echo -e "${CYAN}====================================     Start: Release for $REPO_NAME     ====================================${NC}"
    echo

    # For documentation https://help.github.com/articles/creating-releases/
    DATA="{
        \"tag_name\": \"$VERSION\",
        \"target_commitish\": \"master\",
        \"name\": \"$VERSION\",
        \"body\": \"$DESCRIPTION\",
        \"draft\": false,
        \"prerelease\": $PRE_RELEASE
    }"

    curl -X POST --data "$DATA" https://api.github.com/repos/Azure/$REPO_NAME/releases?access_token=$ACCESS_TOKEN
    echo
    echo -e "${CYAN}====================================     End: Release for $REPO_NAME     ====================================${NC}"
    echo

    if [ -n "$SUB_MODULE" ] && [ "$REPO_NAME" != "pcs-cli" ]; then
        echo
        echo -e "${CYAN}====================================     Start: Building $REPO_NAME     ====================================${NC}"
        echo

        BUILD_PATH="scripts/docker/build"
        if [ "$SUB_MODULE" == "reverse-proxy" ]; then 
            BUILD_PATH="build"
        fi

        # Building docker containers
        /bin/bash $APP_HOME$SUB_MODULE/$BUILD_PATH

        echo
        echo -e "${CYAN}====================================     End: Building $REPO_NAME     ====================================${NC}"
        echo
        
        # Tag containers
        echo -e "${CYAN}Tagging $FROM_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$SOURCE_TAG ==> $TO_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$VERSION${NC}"
        echo
        docker tag $FROM_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$SOURCE_TAG  $TO_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$VERSION

        # Push containers
        echo -e "${CYAN}Pusing container $TO_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$VERSION${NC}"
        docker push $TO_DOCKERHUB_NAMESPACE/$DOCKER_CONTAINER_NAME:$VERSION
    fi
}

check_input

# DOTNET Microservices
tag_build_publish_repo auth               pcs-auth
tag_build_publish_repo device-simulation  pcs-device-simulation
tag_build_publish_repo iothub-manager     pcs-iothub-manager
tag_build_publish_repo storage-adapter    pcs-storage-adapter
tag_build_publish_repo telemetry          pcs-telemetry
tag_build_publish_repo telemetry-agent    pcs-telemetry-agent
tag_build_publish_repo webui              pcs-webui

# PCS CLI
tag_build_publish_repo cli                pcs-cli

# Top Level repo
tag_build_publish_repo reverse-proxy      pcs-remote-monitoring remote-monitoring-nginx $DESCRIPTION

set +e