#! /usr/bin/env bash
_irohms-check-env-vars || exit 1

function _function_test
{
    local function_missing="false"
    # shellcheck disable=SC2048
    for func in $*
    do
        declare -f "$func" > /dev/null || { echo -e "\033[38;5;1mFunction '$func' missing, resource the setup\033[0m" && function_missing="true"; }
    done
    [[ "$function_missing" == "true" ]] && exit 1
}

_function_test _irohms_git_https_or_ssh

# Update installer
if [ ! -d "$IROHMS_DIR" ]
then
    echo "[cucr-get] 'IROHMS_DIR' $IROHMS_DIR doesn't exist"
    exit 1
else
    current_url=$(git -C "$IROHMS_DIR" config --get remote.origin.url)
    new_url=$(_irohms_git_https_or_ssh "$current_url")

    if ! grep -q "^git@.*\.git$\|^https://.*\.git$" <<< "$new_url"
    then
        # shellcheck disable=SC2140
        echo -e "[cucr-get] (cucr-env) new_url: '$new_url' is invalid. It is generated from the current_url: '$current_url'\n"\
"The problem will probably be solved by resourcing the setup"
        exit 1
    fi


    if [ "$current_url" != "$new_url" ]
    then
        git -C "$IROHMS_DIR" remote set-url origin "$new_url"
        echo -e "[cucr-get] Origin has switched to $new_url"
    fi

    if [[ -n "$CI" ]]
    then
        # Do not update with continuous integration but do fetch to refresh available branches
        echo -e "[cucr-get] Fetching cucr-get... "
        git -C "$IROHMS_DIR" fetch
    else
        echo -en "[cucr-get] Updating cucr-get... "

        if ! git -C "$IROHMS_DIR" pull --ff-only --prune
        then
            # prompt for conformation
            exec < /dev/tty
            read -p "[cucr-get] Could not update cucr-get. Continue? " -n 1 -r
            exec <&-
            echo    # (optional) move to a new line
            if [[ ! $REPLY =~ ^[Yy]$ ]]
            then
                exit 1
            fi
        fi
    fi
fi

if [ ! -d "$IROHMS_ENV_TARGETS_DIR" ]
then
    echo "[cucr-get] 'IROHMS_ENV_TARGETS_DIR' $IROHMS_ENV_TARGETS_DIR doesn't exist"
    # shellcheck disable=SC1078,SC1079
    echo """To setup the default cucr-env targets repository do,

cucr-env init-targets git@github.com:juandhv/tue-env-targets.git
"""
    exit 1
else
    current_url=$(git -C "$IROHMS_ENV_TARGETS_DIR" config --get remote.origin.url)
    new_url=$(_irohms_git_https_or_ssh "$current_url")

    if ! grep -q "^git@.*\.git$\|^https://.*\.git$" <<< "$new_url"
    then
        # shellcheck disable=SC2140
        echo -e "[cucr-get] (cucr-env-targets) new_url: '$new_url' is invalid. It is generated from the current_url: '$current_url'\n"\
"The problem will probably be solved by resourcing the setup"
        exit 1
    fi

    if [ "$current_url" != "$new_url" ]
    then
        git -C "$IROHMS_ENV_TARGETS_DIR" remote set-url origin "$new_url"
        echo -e "[cucr-env-targets] Origin has switched to $new_url"
    fi

    echo -en "[cucr-env-targets] Updating targets... "

    if ! { git -C "$IROHMS_ENV_TARGETS_DIR" pull --ff-only --prune && git -C "$IROHMS_ENV_TARGETS_DIR" submodule sync --recursive 1>/dev/null && git -C "$IROHMS_ENV_TARGETS_DIR" submodule update --init --recursive; } && [ -z "$CI" ]
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
    BRANCH=
    for var in "$@"
    do
        if [[ "$var" == --branch* ]]
        then
            # shellcheck disable=SC2001
            BRANCH=$(echo "$var" | sed -e 's/^[^=]*=//g')
        fi
    done

    if [ -n "$BRANCH" ]
    then
        echo -en "[cucr-env-targets] Trying to switch to branch $BRANCH..."
        current_branch=$(git -C "$IROHMS_ENV_TARGETS_DIR" rev-parse --abbrev-ref HEAD)

        if git -C "$IROHMS_ENV_TARGETS_DIR" rev-parse --quiet --verify origin/"$BRANCH" 1>/dev/null
        then
            if [[ "$current_branch" == "$BRANCH" ]]
            then
                echo -en "Already on branch $BRANCH"
            else
                git -C "$IROHMS_ENV_TARGETS_DIR" checkout "$BRANCH" 2>&1
                git -C "$IROHMS_ENV_TARGETS_DIR" submodule sync --recursive 2>&1
                git -C "$IROHMS_ENV_TARGETS_DIR" submodule update --init --recursive 2>&1
                echo -en "Switched to branch $BRANCH"
            fi
        else
            echo # (Optional) move to a new line
            echo -e "[cucr-env-targets] Branch '$BRANCH' does not exist. Current branch is $current_branch"
        fi
    fi
fi

# Run installer
# shellcheck disable=SC1090
source "$IROHMS_DIR"/installer/cucr-install-impl.bash "$@"
