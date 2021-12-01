#! /usr/bin/env bash
# shellcheck disable=SC2016
#
# Package installer (CI script)
# This script uses the Docker image of tue-env and installs the current git
# repository as a tue-env package using tue-install in the CI

# Stop on errors
set -o errexit

# Execute script only in a CI environment
if [ "$CI" != "true" ]
then
    echo -e "\e[35m\e[1mError!\e[0m Trying to execute a CI script in a non-CI environment. Exiting script."
    exit 1
fi

# Standard argument parsing, example: install-package --branch=master --package=ros_robot
for i in "$@"
do
    case $i in
        -p=* | --package=* )
            PACKAGE="${i#*=}" ;;

        -b=* | --branch=* )
        # BRANCH should allways be targetbranch
            BRANCH="${i#*=}" ;;

        -c=* | --commit=* )
            COMMIT="${i#*=}" ;;

        -r=* | --pullrequest=* )
            PULL_REQUEST="${i#*=}" ;;

        -i=* | --image=* )
            IMAGE_NAME="${i#*=}" ;;

        --ssh )
            USE_SSH=true ;;

        --ssh-key=* )
            SSH_KEY="${i#*=}" ;;

        * )
            # unknown option
            if [[ -n "$i" ]]
            then
                echo -e "\e[35m\e[1mUnknown input argument '$i'. Check CI .yml file \e[0m"
                exit 1
            fi ;;
    esac
    shift
done

echo -e "\e[35m\e[1mPACKAGE      = ${PACKAGE}\e[0m"
echo -e "\e[35m\e[1mBRANCH       = ${BRANCH}\e[0m"
echo -e "\e[35m\e[1mCOMMIT       = ${COMMIT}\e[0m"
echo -e "\e[35m\e[1mPULL_REQUEST = ${PULL_REQUEST}\e[0m"

# Set default value for IMAGE_NAME
[ -z "$IMAGE_NAME" ] && IMAGE_NAME='tuerobotics/tue-env'
echo -e "\e[35m\e[1mIMAGE_NAME   = ${IMAGE_NAME}\e[0m"

if [ "$USE_SSH" == "true" ]
then
    SSH_KEY_FINGERPRINT=$(ssh-keygen -lf /dev/stdin <<< "$SSH_KEY" | awk '{print $2}')
    echo -e "\e[35m\e[1mSSH_KEY      = ${SSH_KEY_FINGERPRINT}\e[0m"
fi

echo -e "\e[35m\e[1m
This build can be reproduced locally using the following commands:

tue-get install docker
~/.tue/ci/install-package.sh --package=${PACKAGE} --branch=${BRANCH} --commit=${COMMIT} --pullrequest=${PULL_REQUEST}
~/.tue/ci/build-package.sh --package=${PACKAGE}
~/.tue/ci/test-package.sh --package=${PACKAGE}

Optionally fix your compilation errors and re-run only the last command
\e[0m"

# If packages is non-zero, this is a multi-package repo. In multi-package repo, check if this package needs CI.
# If a single-package repo, CI is always needed.
# shellcheck disable=SC2153
if [ -n "$PACKAGES" ] && ! echo "$PACKAGES" | grep -sqw "$PACKAGE"
then
    echo -e "\e[35m\e[1mNo changes in this package, so no need to run CI\e[0m"
    exit 0
fi
