#! /usr/bin/env bash

function conditional_apt_update
{
    CUCR_APT_GET_UPDATED_FILE=/tmp/cucr_get_apt_get_updated
    if [[ ! -f ${CUCR_APT_GET_UPDATED_FILE} ]]
    then
        echo "[tue-env](bootstrap) sudo apt-get update -qq"
        sudo apt-get update -qq || return 1
        touch ${CUCR_APT_GET_UPDATED_FILE}
    fi
    return 0
}

function installed_or_install
{
    # installed_or_install executable [package]
    # Provide package name if it differs from executable name
    if [[ -z "$1" ]]
    then
        echo "[cucr-env](bootstrap) Error! No package name provided to check for installation."
        return 1
    fi
    local executable package
    executable=$1
    package=$1
    [[ -n "$2" ]] && package=$2
    hash "${executable}" 2> /dev/null && return 0
    conditional_apt_update || { echo "[cucr-env](bootstrap)Error! Could not update apt-get."; return 1; }
    sudo apt-get install --assume-yes -qq "${package}" || { echo "[cucr-env](bootstrap) Error! Could not install ${package}."; return 1; }
    return 0
}

function main
{
    # Make sure curl is installed
    installed_or_install curl
    # Make sure git is installed
    installed_or_install git
    # Make sure lsb-release is installed
    installed_or_install lsb_release lsb-release
    # Make sure python3 is installed
    installed_or_install python3
    # Make sure python3-virtualenv is installed
    installed_or_install virtualenv python3-virtualenv

    # Check if OS is Ubuntu
    DISTRIB_ID="$(lsb_release -si)"
    DISTRIB_RELEASE="$(lsb_release -sr)"

    if [[ "${DISTRIB_ID}" != "Ubuntu" ]]
    then
        echo "[cucr-env](bootstrap) Unsupported OS $DISTRIB_ID. Use Ubuntu."
        return 1
    fi

    # Set ROS version
    CUCR_ROS_DISTRO=
    CUCR_ROS_VERSION=

    for i in "$@"
    do
        case $i in
            --ros-version=* )
                ros_version="${i#*=}"
                ;;
            --ros-distro=* )
                ros_distro="${i#*=}"
                ;;
            --targets-repo=* )
                targets_repo="${i#*=}"
                ;;
            --create-virtualenv=* )
                create_virtualenv="${i#*=}"
                ;;
            * )
                echo "[cucr-env](bootstrap) Error! Unknown argument '${i}' provided to bootstrap script."
                return 1
                ;;
        esac
    done

    case ${DISTRIB_RELEASE} in
        "20.04")
            if [[ "${ros_version}" -eq 2 ]]
            then
                CUCR_ROS_VERSION=2
                if [[ "${ros_distro}" == "foxy" ]]
                then
                    CUCR_ROS_DISTRO="foxy"
                elif [[ "${ros_distro}" == "galactic" ]]
                then
                    CUCR_ROS_DISTRO="galactic"
                elif [[ "${ros_distro}" == "rolling" ]]
                then
                    CUCR_ROS_DISTRO="rolling"
                elif [[ -n "${ros_distro}" ]]
                then
                    echo "[cucr-env](bootstrap) Error! ROS ${ros_distro} is unsupported with cucr-env."
                    return 1
                else
                    CUCR_ROS_DISTRO="galactic"
                    echo "[cucr-env](bootstrap) Using default ROS_DISTRO '${CUCR_ROS_DISTRO}' with ROS_VERSION '${CUCR_ROS_VERSION}'"
                fi
            elif [[ "${ros_version}" -eq 1 ]]
            then
                CUCR_ROS_DISTRO="noetic"
                CUCR_ROS_VERSION=1
            elif [[ -n "${ros_version}" ]]
            then
                echo "[cucr-env](bootstrap) Error! ROS ${ros_version} is unsupported with cucr-env."
                return 1
            else
                CUCR_ROS_DISTRO="noetic"
                CUCR_ROS_VERSION=1
                echo "[cucr-env](bootstrap) Using default ROS_DISTRO '${CUCR_ROS_DISTRO}' with ROS_VERSION '${CUCR_ROS_VERSION}'"
            fi
            ;;
        "22.04")
            if [[ -n "${ros_version}" ]] && [[ "${ros_version}" -ne 2 ]]
            then
                 echo "[cucr-env](bootstrap) Error! Only ROS version 2 is supported with ubuntu 22.04 and newer"
                 return 1
            fi
            CUCR_ROS_VERSION=2

            if [[ "${ros_distro}" == "humble" ]]
            then
                CUCR_ROS_DISTRO="humble"
            elif [[ "${ros_distro}" == "rolling" ]]
            then
                CUCR_ROS_DISTRO="rolling"
            elif [[ -n "${ros_distro}" ]]
            then
                echo "[cucr-env](bootstrap) Error! ROS ${ros_distro} is unsupported with cucr-env."
                return 1
            else
                CUCR_ROS_DISTRO="humble"
                echo "[cucr-env](bootstrap) Using default ROS_DISTRO '${CUCR_ROS_DISTRO}' with ROS_VERSION '${CUCR_ROS_VERSION}'"
            fi
            ;;
        *)
            echo "[cucr-env](bootstrap) Ubuntu ${DISTRIB_RELEASE} is unsupported. Please use one of Ubuntu 20.04 or 22.04."
            return 1
            ;;
    esac

    # Script variables
    env_url="git@github.com:juandhv/tue-env.git"
    { [[ -n "${targets_repo}" ]] && env_targets_url="${targets_repo}"; } || env_targets_url="git@github.com:juandhv/tue-env-targets.git"
    [[ -n "${create_virtualenv}" ]] || create_virtualenv="true"
    env_dir="${HOME}/.cucr"
    workspace="ros-${CUCR_ROS_DISTRO}"
    workspace_dir="${HOME}/ros/${CUCR_ROS_DISTRO}"

    # Move old environments and installer
    if [[ -d "${env_dir}" ]] && [[ -z "${CI}" ]]
    then
        FILES=$(find "${env_dir}"/user/envs -maxdepth 1 -type f)
        date_now=$(date +%F_%R)
        for env in ${FILES}
        do
            mv -f "$(cat "${env}")" "$(cat "${env}")"."${date_now}"
        done
        mv -f "${env_dir}" "${env_dir}"."${date_now}"
    fi

    # If in CI with Docker, then clone cucr-env with BRANCH when not testing a PR
    if [[ "${CI}" == "true" ]] && [[ "${DOCKER}" == "true" ]]
    then
        # Docker has a default value as false for PULL_REQUEST
        if [[ "${PULL_REQUEST}" == "false" ]]
        then
            if [[ -n "${COMMIT}" ]]
            then
                if [[ -n "${BRANCH}" ]]
                then
                    echo -e "[cucr-env](bootstrap) Cloning cucr-env repository (tue-env from CardiffUniversityComputationalRobotics fork) with branch: ${BRANCH} at commit: ${COMMIT}"
                    git clone -q --single-branch --branch "${BRANCH}" "${env_url}" "${env_dir}"
                else
                    echo -e "[cucr-env](bootstrap) Cloning cucr-env repository (tue-env from CardiffUniversityComputationalRobotics fork) with default branch at commit: ${COMMIT}"
                    git clone -q --single-branch "${env_url}" "${env_dir}"
                fi
                git -C "${env_dir}" reset --hard "${COMMIT}"
            else
                echo -e "[cucr-env](bootstrap) Error! CI branch or commit is unset"
                return 1
            fi
        else
            echo -e "[cucr-env](bootstrap) Testing Pull Request"
            [[ -z "${REF_NAME}" ]] && { echo "[cucr-env](bootstrap) Error! Environment variable REF_NAME is not set."; return 1; }

            git clone -q --depth=10 "${env_url}" "${env_dir}"
            git -C "${env_dir}" fetch origin "${REF_NAME}"/"${PULL_REQUEST}"/merge:PULLREQUEST || { echo "[cucr-env](bootstrap) Error! Could not fetch refs"; return 1; }
            git -C "${env_dir}" checkout PULLREQUEST
        fi
    else
        # Update installer
        echo -e "[cucr-env](bootstrap) Cloning cucr-env repository (tue-env from CardiffUniversityComputationalRobotics fork)"
        git clone "${env_url}" "${env_dir}"
    fi

    # Source the installer commands
    # No need to follow to a file which is already checked by CI
    # shellcheck disable=SC1090
    source "${env_dir}"/setup_cucr.bash

    # Create ros environment directory
    mkdir -p "${workspace_dir}"

    # Initialize ros environment directory incl. targets
    cucr-env init "${workspace}" "${workspace_dir}" "--create-virtualenv=${create_virtualenv}" "--targets-url=${env_targets_url}"

    # Configure environment
    cucr-env config "${workspace}" set "CUCR_ROS_DISTRO" "${CUCR_ROS_DISTRO}"
    cucr-env config "${workspace}" set "CUCR_ROS_VERSION" "${CUCR_ROS_VERSION}"

    # Add loading of TU/e tools (cucr-env, cucr-get, etc) to bashrc
    # shellcheck disable=SC2088
    if ! grep -q "${env_dir}/setup_cucr.bash" ~/.bashrc;
    then
        echo "
# Load CUCR (from TU/e) tools
source ${env_dir}/setup_cucr.bash" >> ~/.bashrc
    fi

    # Set this environment as default
    cucr-env set-default "${workspace}"

    # Activate the default environment
    # shellcheck disable=SC1090
    source "${env_dir}"/setup_cucr.bash
}

main "$@" || echo "[cucr-env](bootstrap) Error! Could not install cucr-env."