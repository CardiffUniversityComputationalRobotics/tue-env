#! /usr/bin/env bash

# Make sure git is installed
hash git 2> /dev/null || sudo apt-get install --assume-yes -qq git
# Make sure lsb-release is installed
hash lsb_release 2> /dev/null || sudo apt-get install --assume-yes -qq lsb-release

# Check if OS is Ubuntu
# shellcheck disable=SC1091
source /etc/lsb-release

if [ "$DISTRIB_ID" != "Ubuntu" ]
then
    echo "[bootstrap] Unsupported OS $DISTRIB_ID. Use Ubuntu."
    exit 1
fi

# Set ROS version
case $DISTRIB_RELEASE in
    "16.04")
        IROHMS_ROS_DISTRO=kinetic
        ;;
    "18.04")
        IROHMS_ROS_DISTRO=melodic
        ;;
    *)
        echo "[irohms-env](bootstrap) Ubuntu $DISTRIB_RELEASE is unsupported. Use either 16.04 or 18.04"
        exit 1
        ;;
esac

# Move old environments and installer
if [ -d ~/.irohms ] && [ -z "$CI" ]
then
    FILES=$(find ~/.irohms/user/envs -maxdepth 1 -type f)
    date_now=$(date +%F_%R)
    for env in $FILES
    do
        mv -f "$(cat "$env")" "$(cat "$env")"."$date_now"
    done
    mv -f ~/.irohms ~/.irohms."$date_now"
fi

# If in CI with Docker, then clone irohms-env with BRANCH when not testing a PR
if [ "$CI" == "true" ] && [ "$DOCKER" == "true" ]
then
    # Docker has a default value as false for PULL_REQUEST
    if [ "$PULL_REQUEST" == "false" ]
    then
        if [ -n "$COMMIT" ]
        then
            if [ -n "$BRANCH" ]
            then
                echo -e "[irohms-env](bootstrap) Cloning irohms-env repository (tue-env from juandhv fork) with branch: $BRANCH at commit: $COMMIT"
                git clone -q --single-branch --branch "$BRANCH" git@github.com:juandhv/tue-env.git ~/.irohms
            else
                echo -e "[irohms-env](bootstrap) Cloning irohms-env repository (tue-env from juandhv fork) with default branch at commit: $COMMIT"
                git clone -q --single-branch git@github.com:juandhv/tue-env.git ~/.irohms
            fi
            git -C ~/.irohms reset --hard "$COMMIT"
        else
            echo -e "[irohms-env](bootstrap) Error! CI branch or commit is unset"
            return 1
        fi
    else
        echo -e "[irohms-env](bootstrap) Testing Pull Request"
        git clone -q --depth=10 git@github.com:juandhv/tue-env.git ~/.irohms
        git -C ~/.irohms fetch origin pull/"$PULL_REQUEST"/merge:PULLREQUEST
        git -C ~/.irohms checkout PULLREQUEST
    fi
else
    # Update installer
    echo -e "[irohms-env](bootstrap) Cloning irohms-env repository (tue-env from juandhv fork)"
    git clone --branch irohms git@github.com:juandhv/tue-env.git ~/.irohms
fi

# Source the installer commands
# No need to follow to a file which is already checked by CI
# shellcheck disable=SC1090
source ~/.irohms/setup_irohms.bash

# Create ros environment directory
mkdir -p ~/ros/$IROHMS_ROS_DISTRO

# Initialize ros environment directory incl. targets
irohms-env init ros-$IROHMS_ROS_DISTRO ~/ros/$IROHMS_ROS_DISTRO git@github.com:juandhv/tue-env-targets.git

# Set the correct ROS version for this environment
echo "export IROHMS_ROS_DISTRO=$IROHMS_ROS_DISTRO" >> ~/ros/$IROHMS_ROS_DISTRO/.env/setup/user_setup.bash

# Set IROHMS_GIT_USE_SSH to true
echo "export IROHMS_GIT_USE_SSH=true" >> ~/ros/$IROHMS_ROS_DISTRO/.env/setup/user_setup.bash

# Add loading of TU/e tools (irohms-env, irohms-get, etc) to bashrc
# shellcheck disable=SC2088
if ! grep -q '~/.irohms/setup_irohms.bash' ~/.bashrc;
then
    echo '
# Load IROHMS (from TU/e) tools
source ~/.irohms/setup_irohms.bash' >> ~/.bashrc
fi

# Set this environment as default
irohms-env set-default ros-$IROHMS_ROS_DISTRO

# Activate the default environment
# No need to follow to file which is already checked by CI
# shellcheck disable=SC1090
source ~/.irohms/setup_irohms.bash
