#! /usr/bin/env bash

CUCR_SYSTEM_DIR="${CUCR_ENV_DIR}"/system  # This variable is deprecated and will be removed in a future version of the tool
CUCR_WS_DIR="${CUCR_SYSTEM_DIR}"
export CUCR_SYSTEM_DIR
export CUCR_WS_DIR

if [[ -z "${CUCR_REPOS_DIR}" ]]  # Only set this variable if there exists no default in user_setup.bash
then
    CUCR_REPOS_DIR="${CUCR_ENV_DIR}"/repos
    export CUCR_REPOS_DIR
fi

CUCR_RELEASE_DIR="${CUCR_SYSTEM_DIR}"/release
export CUCR_RELEASE_DIR

# ----------------------------------------------------------------------------------------------------
#                                        HELPER FUNCTIONS
# ----------------------------------------------------------------------------------------------------

function _list_subdirs
{
    fs=$(ls "$1")
    for f in $fs
    do
        if [ -d "$1"/"$f" ]
        then
            echo "$f"
        fi
    done
}

# ----------------------------------------------------------------------------------------------------
#                                       APT MIRROR SELECTION
# ----------------------------------------------------------------------------------------------------

function cucr-apt-select-mirror
{
    # Function to set the fastest APT mirror
    # It uses apt-select to generate a new sources.list, based on the current one.
    # All Arguments to this functions are passed on to apt-select, so check the
    # apt-select documentation for all options.
    hash pip3 2> /dev/null|| sudo apt-get install --assume-yes python3-pip
    hash apt-select 2> /dev/null|| sudo python3 -m pip install -U apt-select

    local mem_pwd
    mem_pwd=$PWD
    # shellcheck disable=SC2164
    cd /tmp
    local err_code
    apt-select "$@" 2> /dev/null
    err_code=$?
    if [ $err_code == 4 ]
    then
        echo -e "Fastest apt mirror is the current one"
    elif [ $err_code != 0 ]
    then
        echo -e "Non zero error code return by apt-select: $err_code"
    else
        echo -e "Updating the apt mirror with the fastest one"
        sudo cp /etc/apt/sources.list /etc/apt/sources.list.bk
        sudo cp /tmp/sources.list /etc/apt/sources.list
        echo -e "Cleaning up existing apt lists in /var/lib/apt/lists"
        sudo rm -rf /var/lib/apt/lists/*
        echo -e "Running: sudo apt-get update -qq"
        sudo apt-get update -qq
    fi
    # shellcheck disable=SC2164
    cd "$mem_pwd"
}

# ----------------------------------------------------------------------------------------------------
#                                       GIT LOCAL HOUSEKEEPING
# ----------------------------------------------------------------------------------------------------

function _cucr-git-get-default-branch
{
    # Takes current dir in case $1 is empty
    local default_branch
    default_branch=$(git -C "$1" symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's@^origin/@@')
    [ -z "$default_branch" ] && default_branch=$(git -C "$1" remote show origin 2>/dev/null | grep HEAD | awk '{print $3}')
    echo "$default_branch"
}

export -f _cucr-git-get-default-branch

function __cucr-git-checkout-default-branch
{
    local default_branch
    default_branch=$(_cucr-git-get-default-branch "$1")
    _git_remote_checkout "$1" origin "$default_branch"
}

export -f __cucr-git-checkout-default-branch

function _cucr-git-checkout-default-branch
{
    _cucr-repos-do "__cucr-git-checkout-default-branch"
}

function _cucr-git-clean-local
{
    # Function to remove stale branches from a git repository (which should
    # either be the PWD or one of its parent directories). The function removes
    # stale branches in two layers. First it removes all branches that have been
    # merged in the remote, then it checks for unmerged branches that have been
    # deleted from the remote and prompts for confirmation before removal. If
    # the function is called with "--force-remove" flag, then no confirmation is asked

    local force_remove
    local error_code
    local stale_branches
    local repo_path
    repo_path="$PWD"
    local repo
    repo=$(basename "$repo_path")

    if [ -n "$1" ]
    then
        if [ "$1" == "--force-remove" ]
        then
            force_remove=true
        else
            echo -e "\e[31m[cucr-git-clean-local][Error] Unknown input argument '$1'. Only supported argument is '--force-remove' to forcefully remove unmerged stale branches\e[0m"
            return 1
        fi
    fi

    git fetch -p || { echo -e "\e[31m[cucr-git-clean-local] 'git fetch -p' failed in '$repo'.\e[0m"; return 1; }

    stale_branches=$(git branch --list --format "%(if:equals=[gone])%(upstream:track)%(then)%(refname)%(end)" \
| sed 's,^refs/heads/,,;/^$/d')

    [ -z "$stale_branches" ] && return 0

    # If the current branch is a stale branch then change to the default repo
    # branch before cleanup
    if [[ "$stale_branches" == *$(git rev-parse --abbrev-ref HEAD)* ]]
    then
        # shellcheck disable=SC2119
        __cucr-git-checkout-default-branch

        git pull --ff-only --prune > /dev/null 2>&1
        error_code=$?

        if [ ! $error_code -eq 0 ]
        then
            echo -e "\e[31m[cucr-git-clean-local] Error pulling upstream on default branch of repository '$repo'. Cancelling branch cleanup.\e[0m"
            return 1
        fi
    fi

    local stale_branch stale_branch_count unmerged_stale_branches
    stale_branch_count=0
    unmerged_stale_branches=""
    for stale_branch in $stale_branches
    do
        git branch -d "$stale_branch" > /dev/null 2>&1
        error_code=$?

        # If an error occured in safe deletion of a stale branch, add it to the
        # list of unmerged stale branches which are to be forcefully removed
        # upon confirmation by the user
        if [ ! $error_code -eq 0 ]
        then
            unmerged_stale_branches="${unmerged_stale_branches:+${unmerged_stale_branches} } $stale_branch"
        else
            ((stale_branch_count++))
            if [ "${stale_branch_count}" -eq 1 ]
            then
                echo -e "\e[36m"
                echo -e "Removing stale branches:"
                echo -e "------------------------"
            fi
            echo -e "$stale_branch"
        fi
    done

    # Removal of unmerged stale branches. Not a default operation with the high
    # level command cucr-git-clean-local
    if [ -n "$unmerged_stale_branches" ]
    then
        unmerged_stale_branches=$(echo "$unmerged_stale_branches" | sed -e 's/^[[:space:]]*//' | tr " " "\n")

        # If force_remove is not true then echo the list of unmerged stale
        # branches and echo that the user needs to call the command with
        # --force-remove to remove these branches
        if [ ! "$force_remove" == "true" ]
        then
            echo -e "\e[33m"
            echo -e "Found unmerged stale branches:"
            echo -e "------------------------------"
            echo -e "$unmerged_stale_branches"
            echo
            echo -e "[cucr-git-clean-local] To remove these branches call the command with '--force-remove'"
            echo -e "\e[0m"

            return 0
        fi

        echo
        echo -e "Removing unmerged stale branches:"
        echo -e "---------------------------------"

        local unmerged_stale_branch
        for unmerged_stale_branch in $unmerged_stale_branches
        do
            git branch -D "$unmerged_stale_branch" > /dev/null 2>&1
            error_code=$?

            if [ ! $error_code -eq 0 ]
            then
                echo -e "\e[31m[cucr-git-clean-local] In repository '$repo' error deleting branch: $unmerged_stale_branch\e[0m"
            else
                echo -e "\e[36m$unmerged_stale_branch"
            fi
        done
    fi

    echo
    echo -e "[cucr-git-clean-local] Branch cleanup of repository '$repo' complete\e[0m"
    return 0
}

function cucr-git-clean-local
{
    # Run _cucr-git-clean-local on cucr-env, cucr-env-targets and all current environment
    # repositories safely when no input exists

    if [ -n "$1" ]
    then
        if [ "$1" != "--force-remove" ]
        then
            echo -e "[cucr-git-clean-local][Error] Unknown input argument '$1'. Only supported argument is '--force-remove' to forcefully remove unmerged stale branches"
            return 1
        fi
    fi

    _cucr-repos-do "_cucr-git-clean-local $*"
}

function __cucr-git-clean-local
{
    local IFS options
    IFS=$'\n'
    options="'--force-remove'"
    # shellcheck disable=SC2178
    mapfile -t COMPREPLY < <(compgen -W "$(echo -e "$options")" -- "$cur")
}
complete -F __cucr-git-clean-local cucr-git-clean-local
complete -F __cucr-git-clean-local _cucr-git-clean-local

# ----------------------------------------------------------------------------------------------------
#                                              SSH
# ----------------------------------------------------------------------------------------------------

function _git_split_url
{
    local url
    url=$1

    # The regex can be further constrained using regex101.com
    if ! grep -P -q "^(?:(?:git@[^:]+:)|(?:https://))[^:]+\.git$" <<< "${url}"
    then
        return 1
    fi

    local web_address domain_name repo_address
    if [[ "$url" == *"@"* ]] # SSH
    then
        web_address=${url#git@}
        domain_name=${web_address%%:*}
        repo_address=${web_address#*:}
    else
        web_address=${url#https://}
        domain_name=${web_address%%/*}
        repo_address=${web_address#*/}
    fi
    repo_address=${repo_address%.git}
    echo -e "$domain_name\t$repo_address"
}
export -f _git_split_url # otherwise not available in sourced files

function _git_https
{
    local url
    url=$1
    [[ $url =~ ^https://.*\.git$ ]] && echo "$url" && return 0

    local output
    output=$(_git_split_url "$url")

    if [[ -z "${output}" ]]
    then
        return 1
    fi

    local array domain_name repo_address
    read -r -a array <<< "$output"
    domain_name=${array[0]}
    repo_address=${array[1]}

    echo "https://$domain_name/$repo_address.git"
}
export -f _git_https # otherwise not available in sourced files

function _git_ssh
{
    local url
    url=$1
    [[ $url =~ ^git@.*\.git$ ]] && echo "$url" && return 0

    local output
    output=$(_git_split_url "$url")

    if [[ -z "${output}" ]]
    then
        return 1
    fi

    local array domain_name repo_address
    read -r -a array <<< "$output"
    domain_name=${array[0]}
    repo_address=${array[1]}

    echo "git@$domain_name:$repo_address.git"
}
export -f _git_ssh # otherwise not available in sourced files

function _cucr_git_https_or_ssh
{
    local input_url output_url test_var
    input_url=$1

    # TODO: Remove the use of CUCR_USE_SSH when migration to CUCR_GIT_USE_SSH is complete
    [[ -v "CUCR_USE_SSH" ]] && test_var="CUCR_USE_SSH"

    [[ -v "CUCR_GIT_USE_SSH" ]] && test_var="CUCR_GIT_USE_SSH"

    [[ "$input_url" == *"github"* ]] && [[ -v "CUCR_GITHUB_USE_SSH" ]] && test_var="CUCR_GITHUB_USE_SSH"
    [[ "$input_url" == *"gitlab"* ]] && [[ -v "CUCR_GITLAB_USE_SSH" ]] && test_var="CUCR_GITLAB_USE_SSH"

    if [[ -n "$test_var" && "${!test_var}" == "true" ]]
    then
        output_url=$(_git_ssh "$input_url")
    else
        output_url=$(_git_https "$input_url")
    fi

    if [[ -z "${output_url}" ]]
    then
        return 1
    fi

    echo "$output_url"
}
export -f _cucr_git_https_or_ssh # otherwise not available in sourced files

######################################################################################################################
# Generate the path where a cloned git repository will be stored, based on its url
# Globals:
#   CUCR_REPOS_DIR, used as the base directory of the generated path
# Arguments:
#   URL, A valid git repository url
# Return:
#   Path where the repository must be cloned
######################################################################################################################
function _git_url_to_repos_dir
{
    local url output
    url=$1
    output=$(_git_split_url "$url")

    if [[ -z "${output}" ]]
    then
        return 1
    fi

    local array domain_name repo_address repos_dir
    read -r -a array <<< "$output"
    domain_name=${array[0]}
    repo_address=${array[1]}
    repos_dir="$CUCR_REPOS_DIR"/"$domain_name"/"$repo_address"

    echo "${repos_dir}"
}
export -f _git_url_to_repos_dir # otherwise not available in sourced files

######################################################################################################################
# Perform a deep fetch on a git repository
#
# Arguments:
#   repo_dir, Path to valid git directory
#     If no directory path specified, current dir is assumed
######################################################################################################################
function cucr-git-deep-fetch
{
    local repo_dir
    repo_dir="${1}"

    if [[ -z "${repo_dir}" ]]
    then
        repo_dir="."
    fi

    git -C "${repo_dir}" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git -C "${repo_dir}" remote update
}
export -f cucr-git-deep-fetch

# ----------------------------------------------------------------------------------------------------
#                                            CUCR-MAKE
# ----------------------------------------------------------------------------------------------------

# catkin build/test worflow
# catkin build -DCATKIN_ENABLE_TESTING=OFF # As we don't install test dependencies by default. Test shouldn't be build
# When you want to test, make sure the test dependencies are installed
# catkin build -DCATKIN_ENABLE_TESTING=ON # This will trigger cmake and will create the targets and build the tests
# catkin test # Run the tests. This will not trigger cmake, so it isn't needed to provide -DCATKIN_ENABLE_TESTING=ON.


function cucr-make
{
    [[ -z "${CUCR_ROS_DISTRO}" ]] && { echo -e "\e[31;1mError! cucr-env variable CUCR_ROS_DISTRO not set.\e[0m"; return 1; }

    [[ -z "${CUCR_ROS_VERSION}" ]] && { echo -e "\e[31;1mError! CUCR_ROS_VERSION is not set.\nSet CUCR_ROS_VERSION before executing this function.\e[0m"; return 1; }

    [[ ! -d "${CUCR_SYSTEM_DIR}" ]] && { echo -e "\e[31;1mError! The workspace '${CUCR_SYSTEM_DIR}' does not exist. Run 'cucr-get install ros${CUCR_ROS_VERSION}' first.\e[0m"; return 1; }

    if [[ "${CUCR_ROS_VERSION}" -eq 1 ]]
    then
        local build_tool
        build_tool=""
        if [ -f "$CUCR_SYSTEM_DIR"/devel/.built_by ]
        then
            build_tool=$(cat "$CUCR_SYSTEM_DIR"/build/.built_by)
        fi
        case $build_tool in
        'catkin build')
            /usr/bin/python3 "$(command -v catkin)" build --workspace "$CUCR_SYSTEM_DIR" "$@"
            return $?
            ;;
        '')
            /usr/bin/python3 "$(command -v catkin)" config --init --mkdirs --workspace "$CUCR_SYSTEM_DIR" --extend /opt/ros/"$CUCR_ROS_DISTRO" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCATKIN_ENABLE_TESTING=OFF
            /usr/bin/python3 "$(command -v catkin)" build --workspace "$CUCR_SYSTEM_DIR" "$@"
            touch "$CUCR_SYSTEM_DIR"/devel/.catkin # hack to allow overlaying to this ws while being empty
            ;;
        *)
            echo -e "\e[31;1mError! ${build_tool} is not supported (anymore), use catkin tools\e[0m"
            return 1
            ;;
        esac
    elif [[ "${CUCR_ROS_VERSION}" -eq 2 ]]
    then
        mkdir -p "$CUCR_SYSTEM_DIR"/src

        # Disable symlink install for production
        if [ "${CI_INSTALL}" == "true" ]
        then
            rm -rf "$CUCR_SYSTEM_DIR"/install
            python3 -m colcon --log-base "$CUCR_SYSTEM_DIR"/log build --base-paths "$CUCR_SYSTEM_DIR"/src --build-base "$CUCR_SYSTEM_DIR"/build --install-base "$CUCR_SYSTEM_DIR"/install "$@"
        else
            python3 -m colcon --log-base "$CUCR_SYSTEM_DIR"/log build --merge-install --symlink-install --base-paths "$CUCR_SYSTEM_DIR"/src --build-base "$CUCR_SYSTEM_DIR"/build --install-base "$CUCR_SYSTEM_DIR"/install "$@"
        fi
        return $?
    else
        echo -e "\e[31;1mError! ROS_VERSION '${CUCR_ROS_VERSION}' is not supported by cucr-env.\e[0m"
        return 1
    fi
}
export -f cucr-make

function cucr-make-test
{
    [[ -z "${CUCR_ROS_DISTRO}" ]] && { echo -e "\e[31;1mError! cucr-env variable CUCR_ROS_DISTRO not set.\e[0m"; return 1; }

    [[ -z "${CUCR_ROS_VERSION}" ]] && { echo -e "\e[31;1mError! CUCR_ROS_VERSION is not set.\nSet CUCR_ROS_VERSION before executing this function.\e[0m"; return 1; }

    [[ ! -d "${CUCR_SYSTEM_DIR}" ]] && { echo -e "\e[31;1mError! The workspace '${CUCR_SYSTEM_DIR}' does not exist. Run 'cucr-get install ros${CUCR_ROS_VERSION}' first.\e[0m"; return 1; }

    if [[ "${CUCR_ROS_VERSION}" -eq 1 ]]
    then
        local build_tool
        build_tool=""
        if [ -f "${CUCR_SYSTEM_DIR}"/build/.built_by ]
        then
            build_tool=$(cat "${CUCR_SYSTEM_DIR}"/build/.built_by)
        fi
        case ${build_tool} in
        'catkin build')
            /usr/bin/python3 "$(command -v catkin)" test --workspace "${CUCR_SYSTEM_DIR}" "$@"
            return $?
            ;;
        '')
            echo -e "\e[31;1mError! First initialize the workspace and build it, i.e. using cucr-make, before running tests\e[0m"
            return 1
            ;;
        *)
            echo -e "\e[31;1mError! ${build_tool} is not supported (anymore), use catkin tools\e[0m"
            return 1
            ;;
        esac
    elif [[ "${CUCR_ROS_VERSION}" -eq 2 ]]
    then
        if [[ ! -d "${CUCR_SYSTEM_DIR}"/src ]]
        then
            echo -e "\e[31;1mError! No 'src' directory exists in the workspace '${CUCR_SYSTEM_DIR}'\e[0m"
            return 1
        fi

        if [[ ! -d "${CUCR_SYSTEM_DIR}"/build ]]
        then
            echo -e "\e[31;1mError! No 'build' directory exists in the workspace '${CUCR_SYSTEM_DIR}'. Build the workspace before running tests\e[0m"
            return 1
        fi

        # Disable symlink install for production
        if [ "${CI_INSTALL}" == "true" ]
        then
            python3 -m colcon --log-base "${CUCR_SYSTEM_DIR}"/log test --base-paths "${CUCR_SYSTEM_DIR}"/src --build-base "${CUCR_SYSTEM_DIR}"/build --install-base "${CUCR_SYSTEM_DIR}"/install --executor sequential --event-handlers console_cohesion+ "$@"
        else
            python3 -m colcon --log-base "${CUCR_SYSTEM_DIR}"/log test --merge-install --base-paths "${CUCR_SYSTEM_DIR}"/src --build-base "${CUCR_SYSTEM_DIR}"/build --install-base "${CUCR_SYSTEM_DIR}"/install --executor sequential --event-handlers console_cohesion+ "$@"
        fi
        return $?
    else
        echo -e "\e[31;1mError! ROS_VERSION '${CUCR_ROS_VERSION}' is not supported by cucr-env.\e[0m"
        return 1
    fi
}
export -f cucr-make-test

function cucr-make-test-result
{
    [[ -z "${CUCR_ROS_DISTRO}" ]] && { echo -e "\e[31;1mError! cucr-env variable CUCR_ROS_DISTRO not set.\e[0m"; return 1; }

    [[ -z "${CUCR_ROS_VERSION}" ]] && { echo -e "\e[31;1mError! CUCR_ROS_VERSION is not set.\nSet CUCR_ROS_VERSION before executing this function.\e[0m"; return 1; }

    [[ ! -d "${CUCR_SYSTEM_DIR}" ]] && { echo -e "\e[31;1mError! The workspace '${CUCR_SYSTEM_DIR}' does not exist. Run 'cucr-get install ros${CUCR_ROS_VERSION}' first.\e[0m"; return 1; }

    if [[ "${CUCR_ROS_VERSION}" -eq 1 ]]
    then
        local build_tool
        build_tool=""
        if [ -f "$CUCR_SYSTEM_DIR"/build/.built_by ]
        then
            build_tool=$(cat "$CUCR_SYSTEM_DIR"/build/.built_by)
        fi
        case $build_tool in
        'catkin build')
            python3 "$(command -v catkin)" test_results "${CUCR_SYSTEM_DIR}"/build "$@"
            return $?
            ;;
        '')
            echo -e "\e[31;1mError! First initialize the workspace and build it, i.e. using cucr-make, before running tests and checking the test results\e[0m"
            return 1
            ;;
        *)
            echo -e "\e[31;1mError! ${build_tool} is not supported (anymore), use catkin tools\e[0m"
            return 1
            ;;
        esac
    elif [[ "${CUCR_ROS_VERSION}" -eq 2 ]]
    then
        if [[ ! -d "${CUCR_SYSTEM_DIR}"/src ]]
        then
            echo -e "\e[31;1mError! No 'src' directory exists in the workspace '${CUCR_SYSTEM_DIR}'\e[0m"
            return 1
        fi

        if [[ ! -d "${CUCR_SYSTEM_DIR}"/build ]]
        then
            echo -e "\e[31;1mError! No 'build' directory exists in the workspace '${CUCR_SYSTEM_DIR}'. Build the workspace, run tests before checking test results\e[0m"
            return 1
        fi

        python3 -m colcon --log-base "${CUCR_SYSTEM_DIR}"/log test-result --test-result-base "${CUCR_SYSTEM_DIR}"/build "$@"
        return $?
    else
        echo -e "\e[31;1mError! ROS_VERSION '${CUCR_ROS_VERSION}' is not supported by cucr-env.\e[0m"
        return 1
    fi
}
export -f cucr-make-test-result

function _cucr-make
{
    local cur
    cur=${COMP_WORDS[COMP_CWORD]}

    local options
    [[ "${CUCR_ROS_VERSION}" -eq 2 ]] && options="${options} --packages-select"
    mapfile -t COMPREPLY < <(compgen -W "$(_list_subdirs "${CUCR_SYSTEM_DIR}"/src) ${options}" -- "${cur}")
}

complete -F _cucr-make cucr-make
complete -F _cucr-make cucr-make-test

# ----------------------------------------------------------------------------------------------------
#                                             CUCR-STATUS
# ----------------------------------------------------------------------------------------------------

function _robocup_branch_allowed
{
    local branch robocup_branch
    branch=$1
    robocup_branch=$(_cucr_get_robocup_branch)
    [ -n "$robocup_branch" ] && [ "$branch" == "$robocup_branch" ] && return 0
    # else
    return 1
}

function _cucr_get_robocup_branch
{
    [ -f "$CUCR_DIR"/user/config/robocup ] && cat "$CUCR_DIR"/user/config/robocup
}

function _cucr-repo-status
{
    local name pkg_dir
    name=$1
    pkg_dir=$2

    if [ ! -d "$pkg_dir" ]
    then
        return 1
    fi

    local status vctype

    # Try git
    if git -C "$pkg_dir" rev-parse --git-dir > /dev/null 2>&1
    then
        # Is git
        local res

        if res=$(git -C "$pkg_dir" status . --short --branch 2>&1)
        then
            if echo "$res" | grep -q -E 'behind|ahead' # Check if behind or ahead of branch
            then
                status=$res
            else
                status=$(git -C "$pkg_dir" status . --short)
            fi

            local current_branch
            current_branch=$(git -C "$pkg_dir" rev-parse --abbrev-ref HEAD)

            local test_branches

            # Add branch specified by target
            local target_branch version_cache_file
            version_cache_file="$CUCR_ENV_DIR/.env/version_cache/$(git -C "$pkg_dir" rev-parse --show-toplevel 2>/dev/null)"
            [ -f "$version_cache_file" ] && target_branch=$(cat "$version_cache_file")
            [ -n "$target_branch" ] && test_branches="${test_branches:+${test_branches} }$target_branch"

            # Add default branch
            local default_branch
            default_branch=$(_cucr-git-get-default-branch "$pkg_dir")
            [ -n "$default_branch" ] && test_branches="${test_branches:+${test_branches} }$default_branch"

            # Add robocup branch
            local robocup_branch
            robocup_branch=$(_cucr_get_robocup_branch)
            [ -n "$robocup_branch" ] && test_branches="${test_branches:+${test_branches} }$robocup_branch"

            local allowed
            allowed="false"
            for test_branch in $test_branches
            do
                if [ "$test_branch" == "$current_branch" ]
                then
                    [ -z "$status" ] && return 0
                    # else
                    allowed="true"
                    break
                fi
            done
            [ "$allowed" != "true" ] && echo -e "\e[1m$name\e[0m is on branch '$current_branch'"
        fi
        vctype=git
    else
        vctype=unknown
    fi

    if [ -n "$vctype" ]
    then
        if [ -n "$status" ]
        then
            echo -e ""
            echo -e "\e[38;1mM  \e[0m($vctype) \e[1m$name\e[0m"
            echo -e "--------------------------------------------------"
            echo -e "$status"
            echo -e "--------------------------------------------------"
        fi
    fi
}

# ----------------------------------------------------------------------------------------------------

function _cucr-dir-status
{
    [ -d "$1" ] || return 1

    local fs
    fs=$(ls "$1")
    for f in $fs
    do
        local pkg_dir
        pkg_dir=$1/$f
        _cucr-repo-status "$f" "$pkg_dir"
    done
}

# ----------------------------------------------------------------------------------------------------

function cucr-status
{
    _cucr-dir-status "$CUCR_SYSTEM_DIR"/src
    _cucr-repo-status "cucr-env" "$CUCR_DIR"
    _cucr-repo-status "cucr-env-targets" "$CUCR_ENV_TARGETS_DIR"
}

# ----------------------------------------------------------------------------------------------------

function cucr-git-status
{
    for pkg_dir in "$CUCR_SYSTEM_DIR"/src/*/
    do
        local pkg
        pkg=$(basename "$pkg_dir")

        local branch
        if branch=$(git -C "$pkg_dir" rev-parse --abbrev-ref HEAD 2>&1)
        then
            local hash
            hash=$(git -C "$pkg_dir" rev-parse --short HEAD)
            printf "\e[0;36m%-20s\e[0m %-15s %s\n" "$branch" "$hash" "$pkg"
        fi
    done
}

# ----------------------------------------------------------------------------------------------------
#                                              CUCR-REVERT
# ----------------------------------------------------------------------------------------------------

function cucr-revert
{
    local human_time
    human_time="$*"

    for pkg_dir in "$CUCR_SYSTEM_DIR"/src/*/
    do
        local pkg
        pkg=$(basename "$pkg_dir")

        local branch
        branch=$(git -C "$pkg_dir" rev-parse --abbrev-ref HEAD 2>&1)
        if branch=$(git -C "$pkg_dir" rev-parse --abbrev-ref HEAD 2>&1) && [ "$branch" != "HEAD" ]
        then
            local new_hash current_hash
            new_hash=$(git -C "$pkg_dir"  rev-list -1 --before="$human_time" "$branch")
            current_hash=$(git -C "$pkg_dir"  rev-parse HEAD)

            local newtime
            if git -C "$pkg_dir"  diff -s --exit-code "$new_hash" "$current_hash"
            then
                newtime=$(git -C "$pkg_dir"  show -s --format=%ci)
                printf "\e[0;36m%-20s\e[0m %-15s \e[1m%s\e[0m %s\n" "$branch is fine" "$new_hash" "$newtime" "$pkg"
            else
                local newbranch
                git -C "$pkg_dir"  checkout -q "$new_hash" --
                newbranch=$(git -C "$pkg_dir"  rev-parse --abbrev-ref HEAD 2>&1)
                newtime=$(git -C "$pkg_dir"  show -s --format=%ci)
                echo "$branch" > "$pkg_dir/.do_not_commit_this"
                printf "\e[0;36m%-20s\e[0m %-15s \e[1m%s\e[0m %s\n" "$newbranch based on $branch" "$new_hash" "$newtime" "$pkg"
            fi
        else
            echo "Package $pkg could not be reverted, current state: $branch"
        fi
    done
}

# ----------------------------------------------------------------------------------------------------
#                                              CUCR-REVERT-UNDO
# ----------------------------------------------------------------------------------------------------

function cucr-revert-undo
{
    for pkg_dir in "$CUCR_SYSTEM_DIR"/src/*/
    do
        local pkg
        pkg=$(basename "$pkg_dir")

        if [ -f "$pkg_dir/.do_not_commit_this" ]
        then
            echo "$pkg"
            git -C "$pkg_dir" checkout "$(cat "$pkg_dir"/.do_not_commit_this)" --
            rm "$pkg_dir/.do_not_commit_this"
        fi
    done
    cucr-git-status
}

# ----------------------------------------------------------------------------------------------------
#                                              CUCR-GET
# ----------------------------------------------------------------------------------------------------

function _cucr_show_file
{
    if [ -n "$2" ]
    then
        echo -e "\e[1m[$1] $2\e[0m"
        echo "--------------------------------------------------"
        if hash pygmentize 2> /dev/null
        then
            pygmentize -g "$CUCR_ENV_TARGETS_DIR"/"$1"/"$2"
        else
            cat "$CUCR_ENV_TARGETS_DIR"/"$1"/"$2"
        fi
        echo "--------------------------------------------------"
    else
        echo -e "_cucr_show_file requires target_name and relative file_path in target"
        return 1
    fi
}

function _cucr_generate_setup_file
{
    "$CUCR_DIR"/setup/generate_setup_file_cucr.py || echo "Error during generation of the 'target_setup.bash'"
}

function _cucr_remove_recursively
{
    if [ -z "$1" ] || [ -n "$2" ]
    then
        echo "_cucr_remove_recursively requires and accepts one target"
        echo "provided arguments: $*"
        return 1
    fi

    local target cucr_dependencies_dir cucr_dependencies_on_dir error_code
    target=$1
    cucr_dependencies_dir="$CUCR_ENV_DIR"/.env/dependencies
    cucr_dependencies_on_dir="$CUCR_ENV_DIR"/.env/dependencies-on
    error_code=0

    # If packages depend on the target to be removed, just remove the installed status.
    if [ -f "$cucr_dependencies_on_dir"/"$target" ]
    then
        if [[ -n $(cat "$cucr_dependencies_on_dir"/"$target") ]]
        then
            # depend-on is not empty, so removing the installed status
            echo "[cucr-get] Other targets still depend on $target, so ignoring it"
            return 0
        else
            # depend-on is empty, so remove it and continue to actual removing of the target
            echo "[cucr-get] Deleting empty depend-on file of: $target"
            rm -f "$cucr_dependencies_on_dir"/"$target"
        fi
    fi

    # If no packages depend on this target, remove it and its dependcies.
    if [ -f "$cucr_dependencies_dir"/"$target" ]
    then
        # Iterate over all depencies of target, which is removed.
        while read -r dep
        do
            # Target is removed, so remove yourself from depend-on files of deps
            local dep_dep_on_file tmp_file
            dep_dep_on_file="$cucr_dependencies_on_dir"/"$dep"
            tmp_file=/tmp/temp_depend_on
            if [ -f "$dep_dep_on_file" ]
            then
                while read -r line
                do
                    [[ $line != "$target" ]] && echo "$line"
                done <"$dep_dep_on_file" >"$tmp_file"
                mv "$tmp_file" "$dep_dep_on_file"
                echo "[cucr-get] Removed '$target' from depend-on file of '$dep'"
            else
                echo "$target depends on $dep, so $dep_dep_on_file should exist with $target in it"
                error_code=1
            fi

            # Actually remove the deps
            local dep_error
            _cucr_remove_recursively "$dep"
            dep_error=$?
            if [ $dep_error -gt 0 ]
            then
                error_code=1
            fi

        done < "$cucr_dependencies_dir"/"$target"
        rm -f "$cucr_dependencies_dir"/"$target"
    else
        echo "[cucr-get] No depencies file exist for target: $target"
    fi

    echo "[cucr-get] Fully uninstalled $target and its dependencies"
    return $error_code
}

function cucr-get
{
    if [ -z "$1" ]
    then
        # shellcheck disable=SC1078,SC1079
        echo """cucr-get is a tool for installing and removing packages.

    Usage: cucr-get COMMAND [ARG1 ARG2 ...]

    Possible commands:

        dep              - Shows target dependencies
        install          - Installs a package
        update           - Updates currently installed packages
        remove           - Removes installed package
        list-installed   - Lists all manually installed packages
        show             - Show the contents of (a) package(s)

    Possible options:
        --debug           - Shows more debugging information
        --no-ros-deps     - Do not install ROS dependencies (Breaks the dependency tree, not all setup files will be sourced)
        --doc-depend      - Do install doc dependencies, overules config and --no-ros-deps
        --no-doc-depend   - Do not install doc dependencies, overules config
        --test-depend     - Do install test dependencies, overules config and --no-ros-deps
        --no-test-depend  - Do not install test dependencies, overules config
        --try-branch=name - Try to checkout the branch (or tag) 'name'. This argument can be specified multiple times
                            and all the --try-branch arguments are processed in the reverse order of their declaration,
                            with the last one being the first. 'name' must only be an one word value, not a list or any
                            other type of string.

"""
        return 1
    fi

    local cucr_dep_dir cucr_installed_dir
    cucr_dep_dir=$CUCR_ENV_DIR/.env/dependencies
    cucr_installed_dir=$CUCR_ENV_DIR/.env/installed

    local error_code
    error_code=0

    local cmd
    cmd=$1
    shift

    #Create btrfs snapshot if possible and usefull:
    if [[ -n "$BTRFS_SNAPSHOT" && "$cmd" =~ ^(install|update|remove)$ ]] && { df --print-type / | grep -q btrfs; }
    then
        echo "[cucr-get] Creating btrfs snapshot"
        sudo mkdir -p /snap/root
        sudo btrfs subvolume snapshot / /snap/root/"$(date +%Y-%m-%d_%H:%M:%S)"
    fi

    if [[ "$cmd" =~ ^(install|remove)$ && -z "$1" ]]
    then
       echo "Usage: cucr-get $cmd TARGET [TARGET2 ...]"
       return 1
    fi

    if [[ $cmd == "install" || $cmd == "update" ]]
    then
        if [[ $cmd == "update" ]]
        then
            for target in "$@"
            do
                #Skip options
                [[ $target = '--'* ]] && continue

                if [ -z "$(find "$CUCR_ENV_DIR"/.env/dependencies -maxdepth 1 -name "$target" -type f -printf "%P ")" ]
                then
                    echo "[cucr-get] Package '$target' is not installed."
                    error_code=1
                fi
            done
        fi

        if [ $error_code -eq 0 ]
        then
            "$CUCR_DIR"/installer/cucr-install.bash "$cmd" "$@"
            error_code=$?
            if [ $error_code -eq 0 ]
            then
                _cucr_generate_setup_file
                # shellcheck disable=SC1091
                source "$CUCR_DIR"/setup_cucr.bash
            fi
        fi

        return $error_code
    elif [[ $cmd == "remove" ]]
    then
        local targets_to_remove
        for target in "$@"
        do
            local resolved_targets
            resolved_targets="$(find "$cucr_installed_dir" -maxdepth 1 -name "$target" -type f -printf "%P ")"
            if [ -z "$resolved_targets" ]
            then
                echo "[cucr-get] Package '$target' is not installed."
                error_code=1
            else
                targets_to_remove="${targets_to_remove:+$targets_to_remove }$resolved_targets"
            fi
        done

        if [ $error_code -gt 0 ]
        then
            echo ""
            echo "[cucr-get] No packages where removed."
            return $error_code;
        fi

        if [ -f /tmp/cucr_get_remove_lock ]
        then
            echo "[cucr-get] Can't execute 'remove' as an other run is still busy"
            echo "[cucr-get] If this keeps happening, excute: rm /tmp/cucr_get_remove_lock"
            return 1
        fi

        touch /tmp/cucr_get_remove_lock
        for target in $targets_to_remove
        do
            local target_error
            target_error=0
            _cucr_remove_recursively "$target"
            target_error=$?
            if [ $target_error -gt 0 ]
            then
                error_code=1
                echo "[cucr-get] Problems during uninstalling $target"
            else
                rm "$cucr_installed_dir"/"$target"
                echo "[cucr-get] Succesfully uninstalled: $target"
            fi
        done

        if [ $error_code -eq 0 ]
        then
            echo "[cucr-get] Re-generating the target setup file"
            _cucr_generate_setup_file
        fi

        rm /tmp/cucr_get_remove_lock

        echo ""
        if [ -n "$2" ]
        then
            echo "[cucr-get] The packages were removed from the 'installed list' but still need to be deleted from your workspace."
        else
            echo "[cucr-get] The package was removed from the 'installed list' but still needs to be deleted from your workspace."
        fi
    elif [[ $cmd == "list-installed" ]]
    then
        if [[ "$1" == "-a" ]]
        then
            ls "$cucr_dep_dir"
        else
            ls "$CUCR_ENV_DIR"/.env/installed
        fi
    elif [[ $cmd == "show" ]]
    then
        if [ -z "$1" ]
        then
            echo "[cucr-get](show) Provide at least one target name"
            return 1
        fi
        local firsttarget
        firsttarget=true
        for target in "$@"
        do
            if [[ $firsttarget == false ]]
            then
                echo ""
            fi
            if [ ! -d "$CUCR_ENV_TARGETS_DIR"/"$target" ]
            then
                echo "[cucr-get](show) '$target' is not a valid target"
                firsttarget=false
                continue
            fi

            local firstfile
            local -a files
            firstfile=true
            mapfile -t files < <(find "$CUCR_ENV_TARGETS_DIR"/"$target" -type f)

            # First show the common target files
            local main_target_files
            main_target_files="install.yaml install.bash setup"
            for file in $main_target_files
            do
                for key in "${!files[@]}"
                do
                    if [ "${files[$key]}" == "$CUCR_ENV_TARGETS_DIR"/"$target"/"$file" ]
                    then
                        if [[ $firstfile == false ]]
                        then
                            echo ""
                        fi
                        _cucr_show_file "$target" "$file"
                        firstfile=false
                        unset "files[$key]"
                        files=("${files[@]}")
                        break
                    fi
                done
            done

            # Show all remaining files
            for file in "${files[@]}"
            do
                if [[ $firstfile == false ]]
                then
                    echo ""
                fi
                _cucr_show_file "$target" "${file#*"${CUCR_ENV_TARGETS_DIR}/${target}/"}"
                firstfile=false
            done
            firsttarget=false
        done

    elif [[ $cmd == "dep" ]]
    then
        "$CUCR_DIR"/installer/cucr-get-dep.bash "$@"
    else
        echo "[cucr-get] Unknown command: '$cmd'"
        return 1
    fi
}

function _cucr-get
{
    local cur
    cur=${COMP_WORDS[COMP_CWORD]}

    if [ "$COMP_CWORD" -eq 1 ]
    then
        local IFS options
        IFS=$'\n'
        options="'dep '\n'install '\n'update '\n'remove '\n'list-installed '\n'show '"
        # shellcheck disable=SC2178
        mapfile -t COMPREPLY < <(compgen -W "$(echo -e "$options")" -- "$cur")
    else
        local cmd
        cmd=${COMP_WORDS[1]}
        if [[ $cmd == "install" ]]
        then
            local IFS
            IFS=$'\n'
            # shellcheck disable=SC2178
            mapfile -t COMPREPLY < <(compgen -W "$(echo -e "$(find "$CUCR_ENV_TARGETS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name ".*" -printf "%f\n" | sed "s/.*/'& '/g")\n'--debug '\n'--no-ros-deps '\n'--doc-depend '\n'--no-doc-depend '\n'--test-depend '\n'--no-test-depend '\n'--try-branch='")" -- "$cur")
        elif [[ $cmd == "dep" ]]
        then
            local IFS
            IFS=$'\n'
            # shellcheck disable=SC2178
            mapfile -t COMPREPLY < <(compgen -W "$(echo -e "$(find "$CUCR_ENV_DIR"/.env/dependencies -mindepth 1 -maxdepth 1 -type f -not -name ".*" -printf "%f\n" | sed "s/.*/'& '/g")\n'--plain '\n'--verbose '\n'--ros-only '\n'--all '\n'--level='")" -- "$cur")
        elif [[ $cmd == "update" ]]
        then
            local IFS
            IFS=$'\n'
            # shellcheck disable=SC2178
            mapfile -t COMPREPLY < <(compgen -W "$(echo -e "$(find "$CUCR_ENV_DIR"/.env/dependencies -mindepth 1 -maxdepth 1 -type f -not -name ".*" -printf "%f\n" | sed "s/.*/'& '/g")\n'--debug '\n'--no-ros-deps '\n'--doc-depend '\n'--no-doc-depend '\n'--test-depend '\n'--no-test-depend '\n'--try-branch='")" -- "$cur")
        elif [[ $cmd == "remove" ]]
        then
            local IFS
            IFS=$'\n'
            # shellcheck disable=SC2178
            mapfile -t COMPREPLY < <(compgen -W "$(find "$CUCR_ENV_DIR"/.env/installed -mindepth 1 -maxdepth 1 -type f -not -name ".*" -printf "%f\n" | sed "s/.*/'& '/g")" -- "$cur")
        elif [[ $cmd == "show" ]]
        then
            local IFS
            IFS=$'\n'
            # shellcheck disable=SC2178
            mapfile -t COMPREPLY < <(compgen -W "$(find "$CUCR_ENV_TARGETS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name ".*" -printf "%f\n" | sed "s/.*/'& '/g")" -- "$cur")
        else
            # shellcheck disable=SC2178
            COMPREPLY=""
        fi
    fi
}
complete -o nospace -F _cucr-get cucr-get

# ----------------------------------------------------------------------------------------------------
#                                             CUCR-CHECKOUT
# ----------------------------------------------------------------------------------------------------

function cucr-checkout
{
    if [ -z "$1" ]
    then
        # shellcheck disable=SC1078,SC1079
        echo """Switches all packages to the given branch, if such a branch exists in that package. Usage:

    cucr-checkout BRANCH-NAME [option]

    options:
    --only-pks: cucr-env is not checked-out to the specified branch

"""
        return 1
    fi

    local NO_CUCR_ENV branch
    while test $# -gt 0
    do
        case "$1" in
            --only-pkgs) NO_CUCR_ENV="true"
            ;;
            --*) echo "unknown option $1"; exit 1;
            ;;
            *) branch=$1
            ;;
        esac
        shift
    done

    fs=$(ls -d -1 "$CUCR_SYSTEM_DIR"/src/**)
    if [ -z "$NO_CUCR_ENV" ]
    then
        fs="$CUCR_DIR $CUCR_ENV_TARGETS_DIR $fs"
    fi
    for pkg_dir in $fs
    do
        local pkg
        pkg=${pkg_dir#"${CUCR_SYSTEM_DIR}/src/"}
        if [ -z "$NO_CUCR_ENV" ]
        then
            if [[ $pkg =~ .cucr ]]
            then
                pkg="cucr-env"
            elif [[ $pkg =~ targets ]]
            then
                pkg="cucr-env-targets"
            fi
        fi

        if [ -d "$pkg_dir" ]
        then
            if git -C "$pkg_dir" rev-parse --quiet --verify origin/"$branch" &>/dev/null
            then
                local current_branch
                current_branch=$(git -C "$pkg_dir" rev-parse --abbrev-ref HEAD)
                if [[ "$current_branch" == "$branch" ]]
                then
                    echo -e "\e[1m$pkg\e[0m: Already on branch $branch"
                else
                    local res _checkout_res _checkout_return _submodule_res _submodule_return
                    _checkout_res=$(git -C "$pkg_dir" checkout "$branch" -- 2>&1)
                    _checkout_return=$?
                    [ -n "$_checkout_res" ] && res="${res:+${res} }$_checkout_res"
                    _submodule_res=$(git -C "$pkg_dir" submodule update --init --recursive 2>&1)
                    # shellcheck disable=SC2034
                    _submodule_return=$?
                    [ -n "$_submodule_res" ] && res="${res:+${res} }$_submodule_res"

                    if [ "$_checkout_return" == 0 ] && [ -z "$_submodule_res" ]
                    then
                        echo -e "\e[1m$pkg\e[0m: checked-out $branch"
                    else
                        echo ""
                        echo -e "    \e[1m$pkg\e[0m"
                        echo "--------------------------------------------------"
                        echo -e "\e[38;1m$res\e[0m"
                        echo "--------------------------------------------------"
                    fi
                fi
            fi
        fi
    done
}

# ----------------------------------------------------------------------------------------------------
#                                             CUCR-DEB FUNCTIONS
# ----------------------------------------------------------------------------------------------------

function cucr-deb-generate
{
    [[ -z "${CUCR_ROS_DISTRO}" ]] && { echo -e "\e[31;1mError! cucr-env variable CUCR_ROS_DISTRO not set.\e[0m"; return 1; }

    [[ -z "${CUCR_ROS_VERSION}" ]] && { echo -e "\e[31;1mError! CUCR_ROS_VERSION is not set.\nSet CUCR_ROS_VERSION before executing this function.\e[0m"; return 1; }

    [[ ! -d "${CUCR_SYSTEM_DIR}" ]] && { echo -e "\e[31;1mError! The workspace '${CUCR_SYSTEM_DIR}' does not exist. Run 'cucr-get install ros${CUCR_ROS_VERSION}' first.\e[0m"; return 1; }

    [[ "${CUCR_ROS_VERSION}" -ne 2 ]] && { echo -e "\e[31;1mError! This command is supported only with CUCR_ROS_VERSION=2.\e[0m"; return 1; }

    local packages_list
    if [[ -z "${1}" ]]
    then
        echo -e "\e[33;1mNo packages specified, so packaging the entire workspace. \e[0m"
        for pkg_path in "${CUCR_SYSTEM_DIR}"/src/*
        do
            pkg="$(basename "${pkg_path}")"
            packages_list="${pkg} ${packages_list}"
        done

        if [[ -z "${packages_list}" ]]
        then
            echo -e "\e[31;1mError! No source packages found in workspace to package.\e[0m"
            return 1
        fi
    else
        packages_list="$*"
    fi

    # Check if packages are built
    local PACKAGES_NOT_BUILT
    for package in $packages_list
    do
        if [[ ! -d "${CUCR_SYSTEM_DIR}"/install/"${package}" ]]
        then
            PACKAGES_NOT_BUILT="${PACKAGES_NOT_BUILT} ${package}"
        fi
    done

    if [[ -n "${PACKAGES_NOT_BUILT}" ]]
    then
        echo -e "\e[31;1mThe following packages are not built:\e[0m${PACKAGES_NOT_BUILT}\e[31;1m. Hence cannot be packaged.\e[0m"
        return 1
    fi

    local cur_dir
    cur=${PWD}

    local timestamp
    timestamp="$(date +%Y%m%d%H%M%S)"

    mkdir -p "${CUCR_RELEASE_DIR}"
    cd "${CUCR_RELEASE_DIR}" || return 1

    for package in $packages_list
    do
        local pkg_rel_dir
        pkg_rel_dir="$("${CUCR_DIR}"/installer/generate_deb_control_cucr.py "${CUCR_RELEASE_DIR}" "${CUCR_SYSTEM_DIR}"/src/"${package}"/package.xml "${timestamp}")"


        if [[ ! -d "${pkg_rel_dir}" ]]
        then
            echo -e "\e[31;1mError! Expected release dir for package '${package}' not created.\e[0m"
            cd "${cur_dir}" || return 1
            return 1
        fi

        mkdir -p "${pkg_rel_dir}"/opt/ros/"${CUCR_ROS_DISTRO}"
        cp -r "${CUCR_SYSTEM_DIR}"/install/"${package}"/* "${pkg_rel_dir}"/opt/ros/"${CUCR_ROS_DISTRO}"/

        dpkg-deb --build --root-owner-group "${pkg_rel_dir}"
        rm -rf "${pkg_rel_dir}"
    done

    cd "${cur_dir}" || return
}
export -f cucr-deb-generate

function cucr-deb-gitlab-release
{
    echo -e "\e[32;1mReleasing debian files to GitLab package registry\e[0m"

    local REGISTRY_URL TOKEN

    for i in "$@"
    do
        case $i in
            --registry-url=* )
                REGISTRY_URL="${i#*=}"
                ;;

            --token=* )
                TOKEN="${i#*=}"
                ;;

            * )
                echo -e "\e[31;1mError! Unknown argument ${i}."
                return 1
                ;;
        esac
    done

    if [[ -z "${REGISTRY_URL}" ]] || [[ -z "${TOKEN}" ]]
    then
        echo -e "\e[31;1mError! Mandatory arguments --registry-url and --token not specified"
        return 1
    fi

    for deb in "${CUCR_RELEASE_DIR}"/*
    do
        local deb_pkg pkgwithversion pkg version
        deb_pkg="$(basename "${deb}")"
        pkgwithversion="${deb_pkg%%-build*}"
        pkg="${pkgwithversion%%_*}"
        version="${pkgwithversion##*_}"

        PACKAGE_URL=${REGISTRY_URL}/${pkg}/${version}/${deb_pkg}
        echo -e "\e[35;1mPACKAGE_URL=${PACKAGE_URL}\e[0m"

        curl --header "JOB-TOKEN: ${TOKEN}" --upload-file "${deb}" "${PACKAGE_URL}"
    done
}
export -f cucr-deb-gitlab-release

# ----------------------------------------------------------------------------------------------------
#                                              CUCR-DATA
# ----------------------------------------------------------------------------------------------------

# shellcheck disable=SC1091
source "$CUCR_DIR"/setup/cucr-data.bash

# ----------------------------------------------------------------------------------------------------
#                                             CUCR-ROBOCUP
# ----------------------------------------------------------------------------------------------------

export CUCR_ROBOCUP_BRANCH="rwc2019"

function _cucr-repos-do
{
    # Evaluates the command of the input for cucr-env, cucr-env-targets and all repo's of cucr-robotics.
    # The input can be multiple arguments, but if the input consists of multiple commands
    # seperated by ';' or '&&' the input needs to be captured in a string.

    local mem_pwd
    mem_pwd=${PWD}
    local -a cmd_array
    cmd_array=("$@")

    local repos_dirs
    if [[ -n ${CUCR_REPOS_DO_DIRS} ]]
    then
        repos_dirs=${CUCR_REPOS_DO_DIRS}
    else
        repos_dirs=${CUCR_REPOS_DIR}/github.com/cucr-robotics
        echo -e "No 'CUCR_REPOS_DO_DIRS' set, using: \e[1m${repos_dirs}\e[0m"
    fi

    { [ -n "$CUCR_DIR" ] && cd "$CUCR_DIR"; } || { echo -e "CUCR_DIR '$CUCR_DIR' does not exist"; return 1; }
    echo -e "\e[1m[cucr-env]\e[0m"
    eval "${cmd_array[*]}"

    { [ -n "$CUCR_ENV_TARGETS_DIR" ] && cd "$CUCR_ENV_TARGETS_DIR"; } || { echo -e "CUCR_ENV_TARGETS_DIR '$CUCR_ENV_TARGETS_DIR' does not exist"; return 1; }
    echo -e "\e[1m[cucr-env-targets]\e[0m"
    eval "${cmd_array[*]}"

    for repos_dir in $(echo "${repos_dirs}" | tr ':' '\n')
    do
        for repo_dir in $(find "$(realpath --no-symlinks "${repos_dir}")" -name '.git' -type d -prune -print0 | xargs -0 dirname)
        do
            local repo
            repo=$(realpath --relative-to="${repos_dir}" "${repo_dir}")
            if [[ ${repo} == "." ]]
            then
                repo=$(basename "${repo_dir}")
            fi
            cd "${repo_dir}" || { echo -e "Directory '${repo_dir}' does not exist"; return 1; }
            echo -e "\e[1m[${repo%.git}]\e[0m"
            eval "${cmd_array[*]}"
        done
    done

    # shellcheck disable=SC2164
    cd "${mem_pwd}"
}

function _cucr-add-git-remote
{
    local remote server
    remote=$1
    server=$2

    if [ -z "$2" ]
    then
        echo "Usage: _cucr-add-git-remote REMOTE SERVER

For example:

    _cucr-add-git-remote roboticssrv amigo@roboticssrv.local:
        "
        return 1
    fi

    if [ "$remote" == "origin" ]
    then
        echo -e "\e[1mYou are not allowed to change the remote: 'origin'\e[0m"
        return 1
    fi

    local output
    output="$(_git_split_url "$(git config --get remote.origin.url)")"
    local array repo_address url_extension
    read -r -a array <<< "$output"
    repo_address=${array[1]}
    url_extension="$repo_address.git"

    if [[ "$(git remote)" == *"$remote"* ]]
    then
        local current_url
        current_url=$(git config --get remote."$remote".url)
        if [[ "$current_url" == "$server$url_extension" ]]
        then
            echo -e "remote '$remote' exists with the same url"
            return 0
        fi

        git remote set-url "$remote" "$server$url_extension"
        echo -e "url of remote '$remote' is changed
    from: $current_url
    to: $server$url_extension"
        return 0
    fi
    git remote add "$remote" "$server$url_extension"

    echo -e "remote '$remote' added with url: $server$url_extension"
}

function cucr-add-git-remote
{
    if [ -z "$2" ]
    then
        echo "Usage: cucr-add-git-remote REMOTE SERVER

For example:

    cucr-add-git-remote roboticssrv amigo@roboticssrv.local:
        "
        return 1
    fi

    local remote server
    remote=$1
    server=$2

    if [ "$remote" == "origin" ]
    then
        echo -e "\e[1mYou are not allowed to change the remote: 'origin'\e[0m"
        return 1
    fi

    _cucr-repos-do "_cucr-add-git-remote $remote $server"
}

function __cucr-remove-git-remote
{
    local remote
    remote=$1

    if [ -z "$1" ]
    then
        echo "Usage: __cucr-remove-git-remote REMOTE

For example:

    __cucr-remove-git-remote roboticssrv
        "
        return 1
    fi

    if [ "$remote" == "origin" ]
    then
        echo -e "\e[1mYou are not allowed to remove the remote: 'origin'\e[0m"
        return 1
    fi

    if [[ "$(git remote)" == *"$remote"* ]]
    then
        git remote remove "$remote"
        echo -e "remote '$remote' is removed"
        return 0
    fi

    echo -e "remote '$remote' doesn't exist"
}

function _cucr-remove-git-remote
{
    if [ -z "$1" ]
    then
        echo "Usage: _cucr-remove-git-remote REMOTE

For example:

    _cucr-remove-git-remote roboticssrv
        "
        return 1
    fi

    local remote
    remote=$1

    if [ "$remote" == "origin" ]
    then
        echo -e "\e[1mYou are not allowed to remove the remote: 'origin'\e[0m"
        return 1
    fi

    _cucr-repos-do "__cucr-remove-git-remote $remote"
}

function _git_remote_checkout
{
    if [ -z "$2" ]
    then
        echo "Usage: _git_remote_checkout [REPO_PATH] REMOTE BRANCH

For example:

    _git_remote_checkout roboticssrv robocup
        "
        return 1
    fi

    local repo_path remote branch exists
    if [ -n "$3" ]
    then
        repo_path=$1
        shift
    fi
    remote=$1
    branch=$2
    exists=$(git -C "${repo_path}" show-ref refs/heads/"${branch}" 2>/dev/null)
    if [ -n "$exists" ]
    then
        git -C "${repo_path}" checkout "${branch}" --
        git -C "${repo_path}" branch -u "${remote}"/"${branch}" "${branch}"
    else
        git -C "${repo_path}" checkout --track -b "${branch}" "${remote}"/"${branch}" --
    fi
}

export -f _git_remote_checkout

function cucr-remote-checkout
{
    if [ -z "$2" ]
    then
        echo "Usage: cucr-remote-checkout REMOTE BRANCH

For example:

    cucr-remote-checkout roboticssrv robocup
        "
        return 1
    fi

    local remote branch
    remote=$1
    branch=$2

    _cucr-repos-do "git fetch $remote; _git_remote_checkout $remote $branch"
}

function _cucr-robocup-remote-checkout
{
    if [ -z "$2" ]
    then
        echo "Usage: _cucr-robocup-remote-checkout REMOTE BRANCH

For example:

    _cucr-robocup-remote-checkout roboticssrv robocup
        "
        return 1
    fi

    local remote branch
    remote=$1
    branch=$2

    git fetch "$remote"
    local current_remote
    current_remote=$(git for-each-ref --format='%(upstream:short)' "$(git symbolic-ref -q HEAD)" | awk -F/ '{print $1}')
    if [ "$current_remote" != "$remote" ]
    then
        _git_remote_checkout "$remote" "$branch"
    fi
}

function cucr-robocup-remote-checkout
{
    # same functionality as cucr-remote-checkout, but no arguments needed
    # doesn't perform a checkout, when current branch is already setup
    # to the roboticssrv
    local remote branch
    remote="roboticssrv"
    branch=$CUCR_ROBOCUP_BRANCH

    _cucr-repos-do "_cucr-robocup-remote-checkout $remote $branch"
}

function _cucr-robocup-change-remote
{
    if [ -z "$2" ]
    then
        echo "Usage: _cucr-robocup-change-remote BRANCH REMOTE

For example:

    _cucr-robocup-change-remote robocup origin
        "
        return 1
    fi

    local branch remote
    branch=$1
    remote=$2

    if [ -n "$(git show-ref refs/heads/"$branch")" ]
    then
        if [[ "$(git remote)" == *"$remote"* ]]
        then
            git fetch "$remote"
            if [[ "$(git branch -a)" == *"${remote}/${branch}"* ]]
            then
                git branch -u "$remote"/"$branch" "$branch"
            else
                echo -e "no branch: $branch on remote: $remote"
            fi
        else
            echo -e "no remote: $remote"
        fi
    else
        echo -e "no local branch: $branch"
    fi
}

function cucr-robocup-change-remote
{
    # This changes the remote of the 'BRANCH' branch to 'REMOTE'
    # After this, you local working copies may be behind what was fetched from REMOTE, so run a $ cucr-get update

    # for packages that have a REMOTE as a remote:
    # do a git fetch origin: git fetch
    # Change remote of branch 'BRANCH' to REMOTE: git branch -u REMOTE/BRANCH BRANCH

    if [ -z "$2" ]
    then
        echo "Usage: cucr-robocup-change-remote BRANCH REMOTE

For example:

    cucr-robocup-change-remote robocup origin
        "
        return 1
    fi

    local branch remote
    branch=$1
    remote=$2

    _cucr-repos-do "_cucr-robocup-change-remote $branch $remote"
}

function cucr-robocup-ssh-copy-id
{
    ssh-copy-id amigo@roboticssrv.local
}

function _allow_robocup_branch
{
    # allow CUCR_ROBOCUP_BRANCH as branch in cucr-status
    if [ ! -f "$CUCR_DIR"/user/config/robocup ]
    then
        echo $CUCR_ROBOCUP_BRANCH > "$CUCR_DIR"/user/config/robocup
    fi
}

function _disallow_robocup_branch
{
    # disallow CUCR_ROBOCUP_BRANCH as branch in cucr-status
    if [ -f "$CUCR_DIR"/user/config/robocup ]
    then
        rm "$CUCR_DIR"/user/config/robocup
    fi
}

function cucr-robocup-set-github
{
    cucr-robocup-change-remote $CUCR_ROBOCUP_BRANCH origin
    _cucr-git-checkout-default-branch
    _disallow_robocup_branch
}

function cucr-robocup-set-roboticssrv
{
    cucr-add-git-remote roboticssrv amigo@roboticssrv.local:
    cucr-robocup-remote-checkout
    _allow_robocup_branch
}

function cucr-robocup-set-timezone-robocup
{
    sudo timedatectl set-timezone Europe/Amsterdam
}

function cucr-robocup-set-timezone-home
{
    sudo timedatectl set-timezone Europe/Amsterdam
}

function _ping_bool
{
    if ping -c 1 "$1" 1>/dev/null 2>/dev/null
    then
        return 0
    else
        return 1
    fi
}

function cucr-robocup-install-package
{
    local repos_dir repo_dir
    repos_dir=$CUCR_ENV_DIR/github.com/cucr-robotics
    repo_dir=$repos_dir/${1}.git

    local mem_pwd
    mem_pwd=${PWD}

    local remote server branch
    remote="roboticssrv"
    server="amigo@roboticssrv.local:"
    branch=$CUCR_ROBOCUP_BRANCH

    # If directory already exists, return
    [ -d "$repo_dir" ] && return 0

    git clone "$server"cucr-robotics/"$1".git "$repo_dir"

    [ ! -d "$repo_dir" ] && return 0
    # shellcheck disable=SC2164
    cd "$repo_dir"

    git remote rename origin $remote
    git remote add origin https://github.com/cucr-robotics/"$1".git

    # shellcheck disable=SC2164
    cd "$mem_pwd"

    if [ -f "$repo_dir/package.xml" ]
    then
        if [ ! -h "$CUCR_ENV_DIR"/system/src/"$1" ]
        then
            ln -s "$repo_dir" "$CUCR_ENV_DIR"/system/src/"$1"
        fi
    else
        # multiple packages in one repo
        local fs
        fs=$(find . -mindepth 1 -maxdepth 1 -type d -not -name ".*" -printf "%f\n")
        for pkg in $fs
        do
            local pkg_dir
            pkg_dir=$repo_dir/$pkg
            if [ -f "$pkg_dir/package.xml" ]
            then
                if [ ! -h "$CUCR_ENV_DIR"/system/src/"$pkg" ]
                then
                    ln -s "$pkg_dir" "$CUCR_ENV_DIR"/system/src/"$pkg"
                fi
            fi
        done
    fi

    # mark target as installed
    touch "$CUCR_ENV_DIR"/.env/installed/ros-"$1"
}

function cucr-robocup-update
{
    _cucr-repos-do "git pull --rebase --autostash"

    # Copy rsettings file
    if [ "$ROBOT_REAL" != "true" ]
    then
        local rsettings_file
        rsettings_file=$CUCR_ENV_TARGETS_DIR/cucr-common/rsettings_file
        if [ -f "$rsettings_file" ]
        then
            cp "$rsettings_file" "$CUCR_DIR"/.rsettings
        fi
    fi
}

function cucr-robocup-set-apt-get-proxy
{
    sudo bash -c "echo 'Acquire::http::Proxy \"http://roboticssrv.wtb.cucr.nl:3142\";' > /etc/apt/apt.conf.d/01proxy"
}

function cucr-robocup-unset-apt-get-proxy
{
    sudo rm /etc/apt/apt.conf.d/01proxy
}
