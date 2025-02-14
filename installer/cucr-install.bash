#! /usr/bin/env bash
_cucr-check-env-vars || exit 1

function _function_test
{
    local function_missing
    function_missing="false"
    # shellcheck disable=SC2048
    for func in $*
    do
        declare -f "$func" > /dev/null || { echo -e "\e[38;1mFunction '$func' missing, resource the setup\e[0m" && function_missing="true"; }
    done
    [[ "$function_missing" == "true" ]] && exit 1
}

_function_test _cucr_git_https_or_ssh

# Update installer
if [ ! -d "$CUCR_DIR" ]
then
    echo "[cucr-get] 'CUCR_DIR' $CUCR_DIR doesn't exist"
    exit 1
else
    current_url=$(git -C "$CUCR_DIR" config --get remote.origin.url)
    new_url=$(_cucr_git_https_or_ssh "$current_url")

    if ! grep -q "^git@.*\.git$\|^https://.*\.git$" <<< "$new_url"
    then
        # shellcheck disable=SC2140
        echo -e "[cucr-get] (cucr-env) new_url: '$new_url' is invalid. It is generated from the current_url: '$current_url'\n"\
"The problem will probably be solved by resourcing the setup"
        exit 1
    fi


    if [ "$current_url" != "$new_url" ]
    then
        git -C "$CUCR_DIR" remote set-url origin "$new_url"
        echo -e "[cucr-get] Origin has switched to $new_url"
    fi

    if [[ -n "$CI" ]]
    then
        # Do not update with continuous integration but do fetch to refresh available branches
        echo -e "[cucr-get] Fetching cucr-get... "
        git -C "$CUCR_DIR" fetch
    else
        echo -en "[cucr-get] Updating cucr-get... "

        if ! git -C "$CUCR_DIR" pull --ff-only --prune
        then
            # prompt for conformation
            exec < /dev/tty
            read -p "[cucr-get] Could not update cucr-get. Continue? [y/N]" -n 1 -r
            exec <&-
            echo    # (optional) move to a new line
            if [[ ! $REPLY =~ ^[Yy]$ ]]
            then
                exit 1
            fi
        fi
    fi
fi

if [ ! -d "$CUCR_ENV_TARGETS_DIR" ]
then
    echo "[cucr-get] 'CUCR_ENV_TARGETS_DIR' $CUCR_ENV_TARGETS_DIR doesn't exist"
    # shellcheck disable=SC1078,SC1079
    echo """To setup the default cucr-env targets repository do,

cucr-env init-targets git@github.com:CardiffUniversityComputationalRobotics/tue-env-targets.git
"""
    exit 1
else
    current_url=$(git -C "$CUCR_ENV_TARGETS_DIR" config --get remote.origin.url)
    new_url=$(_cucr_git_https_or_ssh "$current_url")

    if ! grep -q "^git@.*\.git$\|^https://.*\.git$" <<< "$new_url"
    then
        # shellcheck disable=SC2140
        echo -e "[cucr-get] (cucr-env-targets) new_url: '$new_url' is invalid. It is generated from the current_url: '$current_url'\n"\
"The problem will probably be solved by resourcing the setup"
        exit 1
    fi

    if [ "$current_url" != "$new_url" ]
    then
        git -C "$CUCR_ENV_TARGETS_DIR" remote set-url origin "$new_url"
        echo -e "[cucr-env-targets] Origin has switched to $new_url"
    fi

    echo -en "[cucr-env-targets] Updating targets... "

    if ! { git -C "$CUCR_ENV_TARGETS_DIR" pull --ff-only --prune && git -C "$CUCR_ENV_TARGETS_DIR" submodule sync --recursive 1>/dev/null && git -C "$CUCR_ENV_TARGETS_DIR" submodule update --init --recursive; } && [ -z "$CI" ]
    then
        # prompt for conformation
        exec < /dev/tty
        read -p "[cucr-env-targets] Could not update targets. Continue? " -n 1 -r
        exec <&-
        echo    # (optional) move to a new line
        if [[ ! $REPLY =~ ^[Yy]$ ]]
        then
            exit 1
        fi
    fi
fi

if [[ -n "$CI" ]] # With continuous integration try to switch the targets repo to the PR branch
then
    BRANCH=""
    for var in "$@"
    do
        if [[ "${var}" == --try-branch* ]] || [[ "${var}" == --branch* ]]
        then
            # shellcheck disable=SC2001
            BRANCH="$(echo "${var}" | sed -e 's/^[^=]*=//g')${BRANCH:+ ${BRANCH}}"
        fi
    done

    current_branch=$(git -C "${CUCR_ENV_TARGETS_DIR}" rev-parse --abbrev-ref HEAD)

    if ! git -C "${CUCR_ENV_TARGETS_DIR}" rev-parse --quiet --verify origin/"${current_branch}" 1>/dev/null
    then
        echo -e "[cucr-env-targets] Current branch '${current_branch}' isn't available anymore, switching to the default branch"
        __cucr-git-checkout-default-branch "${CUCR_ENV_TARGETS_DIR}"
        git -C "${CUCR_ENV_TARGETS_DIR}" pull --ff-only --prune
        git -C "${CUCR_ENV_TARGETS_DIR}" submodule sync --recursive 2>&1
        git -C "${CUCR_ENV_TARGETS_DIR}" submodule update --init --recursive 2>&1
        current_branch=$(git -C "${CUCR_ENV_TARGETS_DIR}" rev-parse --abbrev-ref HEAD)
        echo -e "[cucr-env-targets] Switched to the default branch, '${current_branch}'"
    fi

    for branch in ${BRANCH}
    do
        echo -en "[cucr-env-targets] Trying to switch to branch '${branch}'..."

        if git -C "${CUCR_ENV_TARGETS_DIR}" rev-parse --quiet --verify origin/"${branch}" 1>/dev/null
        then
            if [[ "${current_branch}" == "${branch}" ]]
            then
                echo -en "Already on branch ${branch}"
            else
                git -C "${CUCR_ENV_TARGETS_DIR}" checkout "${branch}" --recurse-submodules -- 2>&1
                git -C "${CUCR_ENV_TARGETS_DIR}" submodule sync --recursive 2>&1
                git -C "${CUCR_ENV_TARGETS_DIR}" submodule update --init --recursive 2>&1
                echo -e "Switched to branch ${branch}"
            fi
            break
        else
            echo # (Optional) move to a new line
            echo -e "[cucr-env-targets] Branch '${branch}' does not exist. Current branch is '${current_branch}'"
        fi
    done
fi

# Run installer
# shellcheck disable=SC1090
source "$CUCR_DIR"/installer/cucr-install-impl.bash "$@"
