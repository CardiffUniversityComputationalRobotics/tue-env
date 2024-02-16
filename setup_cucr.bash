#! /usr/bin/env bash
CUCR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export CUCR_DIR

# Load cucr-env tool
# shellcheck disable=SC1091
source "$CUCR_DIR"/setup/cucr-env.bash

# ------------------------------------------
# Helper function for checking if all env vars are set
function _cucr-check-env-vars
{
    [ -n "$CUCR_DIR" ] && [ -n "$CUCR_ENV" ] && [ -n "$CUCR_ENV_DIR" ] \
       && [ -n "$CUCR_BIN" ] && [ -n "$CUCR_ENV_TARGETS_DIR" ] && return 0
    echo "[cucr] Not all needed environment variables are set."
    return 1
}
export -f _cucr-check-env-vars

if [ -z "$CUCR_ENV" ]
then
    if [ ! -f "$CUCR_DIR"/user/config/default_env ]
    then
        # No environment, so all environment specific setup below does not need to be sourced
        return 0
    fi

    CUCR_ENV=$(cat "$CUCR_DIR"/user/config/default_env)
    export CUCR_ENV

    if [ ! -f "$CUCR_DIR"/user/envs/"$CUCR_ENV" ]
    then
        echo "[cucr] No such environment: '$CUCR_ENV'"
        return 1
    fi
fi

CUCR_ENV_DIR=$(cat "$CUCR_DIR"/user/envs/"$CUCR_ENV")
export CUCR_ENV_DIR

if [ ! -d "$CUCR_ENV_DIR" ]
then
    echo "[cucr] Environment directory '$CUCR_ENV_DIR' (environment '$CUCR_ENV') does not exist"
    return 1
fi

export CUCR_ENV_TARGETS_DIR=$CUCR_ENV_DIR/.env/targets

if [ ! -d "$CUCR_ENV_TARGETS_DIR" ]
then
    echo "[cucr] Targets directory '$CUCR_ENV_TARGETS_DIR' (environment '$CUCR_ENV') does not exist"
    return 1
fi

if [ -f "$CUCR_ENV_DIR"/.env/setup/user_setup.bash ]
then
    # shellcheck disable=SC1091
    source "$CUCR_ENV_DIR"/.env/setup/user_setup.bash
fi

# -----------------------------------------
# Load all the bash functions
# shellcheck disable=SC1091
source "$CUCR_DIR"/setup/cucr-functions.bash

if [ -f "$CUCR_DIR"/setup/cucr-misc.bash ]
then
    # shellcheck disable=SC1091
    source "$CUCR_DIR"/setup/cucr-misc.bash
fi

export CUCR_BIN=$CUCR_DIR/bin

# .local/bin is needed in the path for all user installs like pip. It gets added automatically on reboot but not on CI
if [[ :$PATH: != *:$HOME/.local/bin:* ]]
then
    export PATH=$HOME/.local/bin${PATH:+:${PATH}}
fi

if [[ :$PATH: != *:$CUCR_BIN:* ]]
then
    export PATH=$CUCR_BIN${PATH:+:${PATH}}
fi

# Source the python virtual environment if it exists
if [[ -d "${CUCR_ENV_DIR}"/.venv/"${CUCR_ENV}" ]]
then
    # shellcheck disable=SC1090
    source "${CUCR_ENV_DIR}"/.venv/"${CUCR_ENV}"/bin/activate
fi

if [ -f "$CUCR_ENV_DIR"/.env/setup/target_setup.bash ]
then
    # shellcheck disable=SC1091
    source "$CUCR_ENV_DIR"/.env/setup/target_setup.bash
fi