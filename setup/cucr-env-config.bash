#! /usr/bin/env bash

# Functions that configure an environment
# All functions should be called cucr-env-XXX. The functions should be in
# this file for it to work and to be available in the auto complete

function _set_export_option
{

    # _set_export_option KEY VALUE FILE
    # Add the following line: 'export KEY=VALUE' to FILE
    # Or changes the VALUE to current value if line already in FILE.

    local key value
    key=${1//\//\\/}
    value=${2//\//\\/}
    sed -i \
        -e '/^#\?\(\s*'"export ${key}"'\s*=\s*\).*/{s//\1'"${value}"'/;:a;n;ba;q}' \
        -e '$a'"export ${key}"'='"${value}" "$3"
}

function cucr-env-git-use-ssh
{
    local option value
    option="CUCR_GIT_USE_SSH"
    value="true"
    _set_export_option "$option" "$value" "$cucr_env_dir"/.env/setup/user_setup.bash

    echo -e "[cucr-env](config) Environment '$env' set to use SSH for git as default"
}

function cucr-env-git-use-https
{
    local option value
    option="CUCR_GIT_USE_SSH"
    value="false"
    _set_export_option "$option" "$value" "$cucr_env_dir"/.env/setup/user_setup.bash

    echo -e "[cucr-env](config) Environment '$env' set to use HTTPS for git as default"
}

function cucr-env-github-use-ssh
{
    local option value
    option="CUCR_GITHUB_USE_SSH"
    value="true"
    _set_export_option "$option" "$value" "$cucr_env_dir"/.env/setup/user_setup.bash

    echo -e "[cucr-env](config) Environment '$env' set to use SSH for GitHub"
}

function cucr-env-github-use-https
{
    local option value
    option="CUCR_GITHUB_USE_SSH"
    value="false"
    _set_export_option "$option" "$value" "$cucr_env_dir"/.env/setup/user_setup.bash

    echo -e "[cucr-env](config) Environment '$env' set to use HTTPS for GitHub"
}

function cucr-env-gitlab-use-ssh
{
    local option value
    option="CUCR_GITLAB_USE_SSH"
    value="true"
    _set_export_option "$option" "$value" "$cucr_env_dir"/.env/setup/user_setup.bash

    echo -e "[cucr-env](config) Environment '$env' set to use SSH for GitLab"
}

function cucr-env-gitlab-use-https
{
    local option value
    option="CUCR_GITLAB_USE_SSH"
    value="false"
    _set_export_option "$option" "$value" "$cucr_env_dir"/.env/setup/user_setup.bash

    echo -e "[cucr-env](config) Environment '$env' set to use HTTPS for GitLab"
}

function cucr-env-install-test-depend
{
    local option value
    option="CUCR_INSTALL_TEST_DEPEND"
    value="true"
    _set_export_option "$option" "$value" "$cucr_env_dir"/.env/setup/user_setup.bash

    echo -e "[cucr-env](config) Environment '$env' set to install test dependencies"
}

function cucr-env-not-install-test-depend
{
    local option value
    option="CUCR_INSTALL_TEST_DEPEND"
    value="false"
    _set_export_option "$option" "$value" "$cucr_env_dir"/.env/setup/user_setup.bash

    echo -e "[cucr-env](config) Environment '$env' set to not install test dependencies"
}

function cucr-env-install-doc-depend
{
    local option value
    option="CUCR_INSTALL_DOC_DEPEND"
    value="true"
    _set_export_option "$option" "$value" "$cucr_env_dir"/.env/setup/user_setup.bash

    echo -e "[cucr-env](config) Environment '$env' set to install doc dependencies"
}

function cucr-env-not-install-doc-depend
{
    local option value
    option="CUCR_INSTALL_DOC_DEPEND"
    value="false"
    _set_export_option "$option" "$value" "$cucr_env_dir"/.env/setup/user_setup.bash

    echo -e "[cucr-env](config) Environment '$env' set to not install doc dependencies"
}

function cucr-env-set
{
    local option value
    option="$1"
    value="$2"
    _set_export_option "$option" "$value" "$cucr_env_dir"/.env/setup/user_setup.bash

    echo -e "[cucr-env](config) Environment '$env' has '$option' set to '$value'"
}

function _main
{
    if [ -z "$1" ]
    then
        echo -e "[cucr-env](config) no environment set or provided"
        exit 1
    else
        local env
        env=$1
        shift

        local cucr_env_dir
        cucr_env_dir="$(cat "$CUCR_DIR"/user/envs/"$env")"

        if [ -z "$1" ]
        then
            edit "$(file --mime-type "${cucr_env_dir}/.env/setup/user_setup.bash" | awk '{print $2}')":"${cucr_env_dir}/.env/setup/user_setup.bash"
        else
            local functions
            functions=$(compgen -A function | grep "cucr-env-")
            functions=${functions//cucr-env-/}
            # shellcheck disable=SC2086
            functions=$(echo $functions | tr ' ' '|')

            local cmd
            cmd=$1
            shift

            eval "
                case $cmd in
                    $functions )
                            cucr-env-$cmd $*;;
                    * )
                        echo -e '[cucr-env](config) Unknown config command: $cmd'
                        exit 1 ;;
                esac"
        fi
    fi
}

_main "$@"
