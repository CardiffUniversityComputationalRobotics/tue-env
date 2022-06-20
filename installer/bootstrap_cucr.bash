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
        CUCR_ROS_DISTRO=kinetic
        ;;
    "18.04")
        CUCR_ROS_DISTRO=melodic
        ;;
    "20.04")
        CUCR_ROS_DISTRO=noetic
        ;;
    *)
        echo "[cucr-env](bootstrap) Ubuntu $DISTRIB_RELEASE is unsupported. Use either 16.04 or 18.04"
        exit 1
        ;;
esac

# Move old environments and installer
if [ -d ~/.cucr ] && [ -z "$CI" ]
then
    FILES=$(find ~/.cucr/user/envs -maxdepth 1 -type f)
    date_now=$(date +%F_%R)
    for env in $FILES
    do
        mv -f "$(cat "$env")" "$(cat "$env")"."$date_now"
    done
    mv -f ~/.cucr ~/.cucr."$date_now"
fi

# If in CI with Docker, then clone cucr-env with BRANCH when not testing a PR
if [ "$CI" == "true" ] && [ "$DOCKER" == "true" ]
then
    # Docker has a default value as false for PULL_REQUEST
    if [ "$PULL_REQUEST" == "false" ]
    then
        if [ -n "$COMMIT" ]
        then
            if [ -n "$BRANCH" ]
            then
                echo -e "[cucr-env](bootstrap) Cloning cucr-env repository (tue-env from CardiffUniversityComputationalRobotics fork) with branch: $BRANCH at commit: $COMMIT"
                git clone -q --single-branch --branch "$BRANCH" git@github.com:CardiffUniversityComputationalRobotics/tue-env.git ~/.cucr
            else
                echo -e "[cucr-env](bootstrap) Cloning cucr-env repository (tue-env from CardiffUniversityComputationalRobotics fork) with default branch at commit: $COMMIT"
                git clone -q --single-branch git@github.com:CardiffUniversityComputationalRobotics/tue-env.git ~/.cucr
            fi
            git -C ~/.cucr reset --hard "$COMMIT"
        else
            echo -e "[cucr-env](bootstrap) Error! CI branch or commit is unset"
            return 1
        fi
    else
        echo -e "[cucr-env](bootstrap) Testing Pull Request"
        git clone -q --depth=10 git@github.com:CardiffUniversityComputationalRobotics/tue-env.git ~/.cucr
        git -C ~/.cucr fetch origin pull/"$PULL_REQUEST"/merge:PULLREQUEST
        git -C ~/.cucr checkout PULLREQUEST
    fi
else
    # Update installer
    echo -e "[cucr-env](bootstrap) Cloning cucr-env repository (tue-env from CardiffUniversityComputationalRobotics fork)"
    git clone --branch cucr git@github.com:CardiffUniversityComputationalRobotics/tue-env.git ~/.cucr
fi

# Source the installer commands
# No need to follow to a file which is already checked by CI
# shellcheck disable=SC1090
source ~/.cucr/setup_cucr.bash

# Create ros environment directory
mkdir -p ~/ros/$CUCR_ROS_DISTRO

# Initialize ros environment directory incl. targets
cucr-env init ros-$CUCR_ROS_DISTRO ~/ros/$CUCR_ROS_DISTRO git@github.com:CardiffUniversityComputationalRobotics/tue-env.git

# Set the correct ROS version for this environment
echo "export CUCR_ROS_DISTRO=$CUCR_ROS_DISTRO" >> ~/ros/$CUCR_ROS_DISTRO/.env/setup/user_setup.bash

# Set CUCR_GIT_USE_SSH to true
echo "export CUCR_GIT_USE_SSH=true" >> ~/ros/$CUCR_ROS_DISTRO/.env/setup/user_setup.bash

# Add loading of TU/e tools (cucr-env, cucr-get, etc) to bashrc
# shellcheck disable=SC2088
if ! grep -q '~/.cucr/setup_cucr.bash' ~/.bashrc;
then
    echo '
# Load CUCR (from TU/e) tools
source ~/.cucr/setup_cucr.bash' >> ~/.bashrc
fi

# Set this environment as default
cucr-env set-default ros-$CUCR_ROS_DISTRO

# Activate the default environment
# No need to follow to file which is already checked by CI
# shellcheck disable=SC1090
source ~/.cucr/setup_cucr.bash
