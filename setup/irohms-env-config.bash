#! /usr/bin/env bash

# Functions that configure an environment
# All functions should be called irohms-env-XXX. The functions should be in
# this file for it to work and to be available in the auto complete

function _set_export_option
{

    # _set_export_option KEY VALUE FILE
    # Add the following line: 'export KEY=VALUE' to FILE
    # Or changes the VALUE to current value if line already in FILE.

    local key=${1//\//\\/}
    local value=${2//\//\\/}
    sed -i \
        -e '/^#\?\(\s*'"export ${key}"'\s*=\s*\).*/{s//\1'"${value}"'/;:a;n;ba;q}' \
        -e '$a'"export ${key}"'='"${value}" "$3"
}

function irohms-env-git-use-ssh
{
    local option="IROHMS_GIT_USE_SSH"
    local value="true"
    _set_export_option "$option" "$value" "$irohms_env_dir"/.env/setup/user_setup.bash

    echo -e "[irohms-env](config) Environment '$env' set to use SSH for git as default"
}

function irohms-env-git-use-https
{
    local option="IROHMS_GIT_USE_SSH"
    local value="false"
    _set_export_option "$option" "$value" "$irohms_env_dir"/.env/setup/user_setup.bash

    echo -e "[irohms-env](config) Environment '$env' set to use HTTPS for git as default"
}

function irohms-env-github-use-ssh
{
    local option="IROHMS_GITHUB_USE_SSH"
    local value="true"
    _set_export_option "$option" "$value" "$irohms_env_dir"/.env/setup/user_setup.bash

    echo -e "[irohms-env](config) Environment '$env' set to use SSH for GitHub"
}

function irohms-env-github-use-https
{
    local option="IROHMS_GITHUB_USE_SSH"
    local value="false"
    _set_export_option "$option" "$value" "$irohms_env_dir"/.env/setup/user_setup.bash

    echo -e "[irohms-env](config) Environment '$env' set to use HTTPS for GitHub"
}

function irohms-env-gitlab-use-ssh
{
    local option="IROHMS_GITLAB_USE_SSH"
    local value="true"
    _set_export_option "$option" "$value" "$irohms_env_dir"/.env/setup/user_setup.bash

    echo -e "[irohms-env](config) Environment '$env' set to use SSH for GitLab"
}

function irohms-env-gitlab-use-https
{
    local option="IROHMS_GITLAB_USE_SSH"
    local value="false"
    _set_export_option "$option" "$value" "$irohms_env_dir"/.env/setup/user_setup.bash

    echo -e "[irohms-env](config) Environment '$env' set to use HTTPS for GitLab"
}

function irohms-env-install-test-depend
{
    local option="IROHMS_INSTALL_TEST_DEPEND"
    local value="true"
    _set_export_option "$option" "$value" "$irohms_env_dir"/.env/setup/user_setup.bash

    echo -e "[irohms-env](config) Environment '$env' set to install test dependencies"
}

function irohms-env-not-install-test-depend
{
    local option="IROHMS_INSTALL_TEST_DEPEND"
    local value="false"
    _set_export_option "$option" "$value" "$irohms_env_dir"/.env/setup/user_setup.bash

    echo -e "[irohms-env](config) Environment '$env' set to not install test dependencies"
}

function irohms-env-install-doc-depend
{
    local option="IROHMS_INSTALL_DOC_DEPEND"
    local value="true"
    _set_export_option "$option" "$value" "$irohms_env_dir"/.env/setup/user_setup.bash

    echo -e "[irohms-env](config) Environment '$env' set to install doc dependencies"
}

function irohms-env-not-install-doc-depend
{
    local option="IROHMS_INSTALL_DOC_DEPEND"
    local value="false"
    _set_export_option "$option" "$value" "$irohms_env_dir"/.env/setup/user_setup.bash

    echo -e "[irohms-env](config) Environment '$env' set to not install doc dependencies"
}

if [ -z "$1" ]
then
    echo -e "[irohms-env](config) no environment set or provided"
    exit 1
else
    env=$1
    shift

    irohms_env_dir="$(cat "$IROHMS_DIR"/user/envs/"$env")"

    if [ -z "$1" ]
    then
        edit "${irohms_env_dir}/.env/setup/user_setup.bash"
    else
        functions=$(compgen -A function | grep "irohms-env-")
        functions=${functions//irohms-env-/}
        # shellcheck disable=SC2086
        functions=$(echo $functions | tr ' ' '|')

        cmd=$1
        shift

        eval "
            case $cmd in
                $functions )
                        irohms-env-$cmd $*;;
                * )
                    echo -e '[irohms-env](config) Unknown config command: $cmd'
                    exit 1 ;;
            esac"
    fi
fi
