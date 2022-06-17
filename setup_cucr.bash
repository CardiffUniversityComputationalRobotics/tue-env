#! /usr/bin/env bash
IROHMS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export IROHMS_DIR

# Load cucr-env tool
# shellcheck disable=SC1090
source "$IROHMS_DIR"/setup/cucr-env.bash

# ------------------------------------------
# Helper function for checking if all env vars are set
function _irohms-check-env-vars
{
    [ -n "$IROHMS_DIR" ] && [ -n "$IROHMS_ENV" ] && [ -n "$IROHMS_ENV_DIR" ] \
       && [ -n "$IROHMS_BIN" ] && [ -n "$IROHMS_ENV_TARGETS_DIR" ] && return 0
    echo "[cucr] Not all needed environment variables are set."
    return 1
}
export -f _irohms-check-env-vars

if [ -z "$IROHMS_ENV" ]
then
    if [ ! -f "$IROHMS_DIR"/user/config/default_env ]
    then
        # No environment, so all environment specific setup below does not need to be sourced
        return 0
    fi

    IROHMS_ENV=$(cat "$IROHMS_DIR"/user/config/default_env)
    export IROHMS_ENV

    if [ ! -f "$IROHMS_DIR"/user/envs/"$IROHMS_ENV" ]
    then
        echo "[cucr] No such environment: '$IROHMS_ENV'"
        return 1
    fi
fi

IROHMS_ENV_DIR=$(cat "$IROHMS_DIR"/user/envs/"$IROHMS_ENV")
export IROHMS_ENV_DIR

if [ ! -d "$IROHMS_ENV_DIR" ]
then
    echo "[cucr] Environment directory '$IROHMS_ENV_DIR' (environment '$IROHMS_ENV') does not exist"
    return 1
fi

export IROHMS_ENV_TARGETS_DIR=$IROHMS_ENV_DIR/.env/targets

if [ ! -d "$IROHMS_ENV_TARGETS_DIR" ]
then
    echo "[cucr] Targets directory '$IROHMS_ENV_TARGETS_DIR' (environment '$IROHMS_ENV') does not exist"
    return 1
fi

if [ -f "$IROHMS_ENV_DIR"/.env/setup/user_setup.bash ]
then
    # shellcheck disable=SC1090
    source "$IROHMS_ENV_DIR"/.env/setup/user_setup.bash
fi

# -----------------------------------------
# Load all the bash functions
# shellcheck disable=SC1090
source "$IROHMS_DIR"/setup/cucr-functions.bash

if [ -f "$IROHMS_DIR"/setup/cucr-misc.bash ]
then
    # shellcheck disable=SC1090
    source "$IROHMS_DIR"/setup/cucr-misc.bash
fi

export IROHMS_BIN=$IROHMS_DIR/bin

# .local/bin is needed in the path for all user installs like pip. It gets added automatically on reboot but not on CI
if [[ :$PATH: != *:$HOME/.local/bin:* ]]
then
    export PATH=$HOME/.local/bin${PATH:+:${PATH}}
fi

if [[ :$PATH: != *:$IROHMS_BIN:* ]]
then
    export PATH=$IROHMS_BIN${PATH:+:${PATH}}
fi

if [ -f "$IROHMS_ENV_DIR"/.env/setup/target_setup.bash ]
then
    # shellcheck disable=SC1090
    source "$IROHMS_ENV_DIR"/.env/setup/target_setup.bash
fi
