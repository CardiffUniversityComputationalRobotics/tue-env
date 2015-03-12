#!/bin/bash

TUE_DEV_DIR=$TUE_ENV_DIR/dev
TUE_SYSTEM_DIR=$TUE_ENV_DIR/system

# ----------------------------------------------------------------------------------------------------
#                                        HELPER FUNCTIONS
# ----------------------------------------------------------------------------------------------------

function _list_subdirs
{
    fs=`ls $1`
    for f in $fs
    do
        if [ -d $1/$f ]
        then
            echo $f
        fi
    done
}

# ----------------------------------------------------------------------------------------------------
#                                           TUE-CREATE
# ----------------------------------------------------------------------------------------------------

function tue-create
{
    if [ -z "$1" ]
    then
        echo "Usage: tue-create TYPE [ ARG1 ARG2 ... ]"
        return 1
    fi

    creation_type=$1

    # remove the first argument (which contained the creation type)
    shift

    if [ -f $TUE_DIR/create/$creation_type/create.bash ]
    then
        source $TUE_DIR/create/$creation_type/create.bash
    elif [ $TUE_DIR/create/$creation_type/create ]
    then
        $TUE_DIR/create/$creation_type/create $@
    else
        echo "tue-create: invalid creation type: '$creation_type'."
        return 1
    fi
}

function _tue-create
{
    local cur=${COMP_WORDS[COMP_CWORD]}
    local prev=${COMP_WORDS[COMP_CWORD-1]}

    if [ $COMP_CWORD -eq 1 ]; then
        COMPREPLY=( $(compgen -W "`_list_subdirs $TUE_DIR/create`" -- $cur) )
    fi
}
complete -F _tue-create tue-create

# ----------------------------------------------------------------------------------------------------
#                                            TUE-MAKE
# ----------------------------------------------------------------------------------------------------

function tue-make
{
    # compile non-ros packages if needed
    if [ -d $TUE_ENV_DIR/pkgs ]
    then
        $TUE_DIR/make/pre-configure.bash
        $TUE_DIR/make/configure.bash
        $TUE_DIR/make/make.bash
        $TUE_DIR/make/post-make.bash
    fi    

    catkin_make --directory $TUE_SYSTEM_DIR -DCMAKE_BUILD_TYPE=RelWithDebInfo $@
}

function tue-make-system
{
    catkin_make_isolated --directory $TUE_SYSTEM_DIR -DCMAKE_BUILD_TYPE=RelWithDebInfo $@	
}

function tue-make-dev
{
    catkin_make --directory $TUE_DEV_DIR -DCMAKE_BUILD_TYPE=RelWithDebInfo $@
}

function tue-make-dev-isolated
{
    catkin_make_isolated --directory $TUE_DEV_DIR -DCMAKE_BUILD_TYPE=RelWithDebInfo $@
}

# ----------------------------------------------------------------------------------------------------
#                                              TUE-DEV
# ----------------------------------------------------------------------------------------------------

function tue-dev
{
    if [ -z "$1" ]
    then
        _list_subdirs $TUE_DEV_DIR/src
        return 0
    fi

    for pkg in $@
    do     
        if [ ! -d $TUE_SYSTEM_DIR/src/$pkg ]
        then
            echo "[tue-dev] '$pkg' does not exist in the system workspace."
        elif [ -d $TUE_DEV_DIR/src/$pkg ]
        then
            echo "[tue-dev] '$pkg' is already in the dev workspace."
        else
            ln -s $TUE_SYSTEM_DIR/src/$pkg $TUE_DEV_DIR/src/$pkg
        fi
    done

    # Call rospack such that the linked directories are indexed
    local tmp=`rospack profile`
}

function tue-dev-clean
{
    for f in `_list_subdirs $TUE_DEV_DIR/src`
    do
        # Test if f is a symbolic link
        if [[ -L $TUE_DEV_DIR/src/$f ]]
        then
            echo "Cleaned '$f'"
            rm $TUE_DEV_DIR/src/$f
        fi
    done

    rm -rf $TUE_DEV_DIR/devel/share
    rm -rf $TUE_DEV_DIR/devel/etc
    rm -rf $TUE_DEV_DIR/devel/include
    rm -rf $TUE_DEV_DIR/devel/lib
    rm -rf $TUE_DEV_DIR/build
}

function _tue-dev
{
    local cur=${COMP_WORDS[COMP_CWORD]}
    local prev=${COMP_WORDS[COMP_CWORD-1]}

    COMPREPLY=( $(compgen -W "`_list_subdirs $TUE_SYSTEM_DIR/src`" -- $cur) )
}
complete -F _tue-dev tue-dev

# ----------------------------------------------------------------------------------------------------
#                                             TUE-STATUS
# ----------------------------------------------------------------------------------------------------

function _tue-repo-status
{
    local name=$1
    local pkg_dir=$2

    if [ ! -d $pkg_dir ]
    then
        return
    fi

    local status=
    local vctype=

    if [ -d $pkg_dir/.svn ]
    then
        status=`svn status $pkg_dir`
        vctype=svn
    else
        # Try git

        cd $pkg_dir
        res=$(git status . --short --branch 2>&1)
        if [ $? -eq 0 ]
        then
            # Is git
            if echo "$res" | grep -q '\['   # Check if ahead of branch
            then
                status=$res
            else
                status=`git status . --short`
            fi

            local current_branch=`git rev-parse --abbrev-ref HEAD`
            if [ $current_branch != "master" ] && [ $current_branch != "hydro-devel" ]
            then
                echo -e "\033[1m$name\033[0m is on branch '$current_branch'"
            fi

        fi  

        cd - &> /dev/null
        vctype=git
    #else
    #    show=false
    fi

    if [ -n "$vctype" ]
    then
        if [ -n "$status" ]; then
            echo ""
            echo -e "\033[38;5;1mM  \033[0m($vctype) \033[1m$name\033[0m"
            echo "--------------------------------------------------"
            echo -e "$status"
            echo "--------------------------------------------------"
        fi 
    fi    
}

# ----------------------------------------------------------------------------------------------------

function tue-status
{
    fs=`ls $TUE_SYSTEM_DIR/src`
    for f in $fs
    do
        pkg_dir=$TUE_SYSTEM_DIR/src/$f
        _tue-repo-status $f $pkg_dir        
    done

    _tue-repo-status $TUE_DIR $TUE_DIR
}

# ----------------------------------------------------------------------------------------------------

function tue-git-status
{
    local output=""

    fs=`ls $TUE_SYSTEM_DIR/src`
    for pkg in $fs
    do
        pkg_dir=$TUE_SYSTEM_DIR/src/$pkg

        if [ -d $pkg_dir ]
        then
            cd $pkg_dir
            branch=$(git rev-parse --abbrev-ref HEAD 2>&1)
            if [ $? -eq 0 ]
            then
                hash=$(git rev-parse --short HEAD)
                printf "\e[0;36m%-20s\033[0m %-15s %s\n" "$branch" "$hash" "$pkg"
            fi
        fi
    done
}

# ----------------------------------------------------------------------------------------------------
#                                              TUE-GET
# ----------------------------------------------------------------------------------------------------

function _tue_depends1
{
    local tue_dep_dir=$TUE_ENV_DIR/.env/dependencies

    if [ -z "$1" ]
    then
        echo "Usage: tue-depends PACKAGE"
        return 1
    fi

    if [ ! -f $tue_dep_dir/$1 ]
    then
        echo "Package '$1' not installed"
        return 1
    fi

    cat $tue_dep_dir/$1
}

function randid
{
    </dev/urandom tr -dc '0123456789abcdef' | head -c16; echo ""
}

function tue-get
{
    if [ -z "$1" ]
    then
        echo """tue-get is a tool for installing and removing packages.

    Usage: tue-get COMMAND [ARG1 ARG2 ...]

    Possible commands:

        dep            - Shows target dependencies
        install        - Installs a package
        update         - Updates currently installed packages
        remove         - Removes installed package
        list-installed - Lists all manually installed packages

"""
        return 1
    fi

    local tue_dep_dir=$TUE_ENV_DIR/.env/dependencies
    local tue_installed_dir=$TUE_ENV_DIR/.env/installed

    cmd=$1
    shift

    if [[ $cmd == "install" ]]
    then        
        if [ -z "$1" ]
        then
            echo "Usage: tue-get install TARGET [TARGET2 ...]"
            return 1
        fi

        $TUE_DIR/installer/scripts/tue-install $@
        error_code=$?

        if [ $error_code -eq 0 ]
        then
            # Mark targets as installed
            TUE_INSTALL_INSTALLED_DIR=$TUE_ENV_DIR/.env/installed
            mkdir -p $TUE_INSTALL_INSTALLED_DIR

            for target in $@
            do            
                touch $TUE_INSTALL_INSTALLED_DIR/$1
            done
        fi

        [ $error_code -eq 0 ] && source ~/.bashrc

        return $error_code
    elif [[ $cmd == "update" ]]
    then
        error_code=0
        for target in $@
        do
            if [ ! -f $TUE_ENV_DIR/.env/dependencies/$target ]
            then
                echo "[tue-get] Package '$target' is not installed."
                error_code=1
            fi
        done

        if [ $error_code -eq 0 ]
        then
            $TUE_DIR/installer/scripts/tue-install $@
            error_code=$?
            [ $error_code -eq 0 ] && source ~/.bashrc 
        fi
    
        return $error_code       
    elif [[ $cmd == "remove" ]]
    then
        if [ -z "$1" ]
        then
            echo "Usage: tue-get remove TARGET [TARGET2 ...]"
            return 1
        fi

        error=0
        for target in $@
        do
            if [ ! -f $tue_installed_dir/$target ]
            then
                echo "[tue-get] Package '$target' is not installed."
                error=1
            fi
        done        

        if [ $error -gt 0 ];
        then
            echo ""
            echo "[tue-get] No packages where removed."
            return $error;
        fi

        for target in $@
        do
            rm $tue_installed_dir/$target 
        done

        echo ""
        if [ -n "$2" ]; then
            echo "The packages were removed from the 'installed list' but still need to be deleted from your workspace."
        else
            echo "The package was removed from the 'installed list' but still needs to be deleted from your workspace."
        fi
    elif [[ $cmd == "list-installed" ]]
    then
        if [[ "$1" == "-a" ]]
        then
            ls $tue_dep_dir
        else
            ls $TUE_ENV_DIR/.env/installed
        fi
    elif [[ $cmd == "dep" ]]
    then
        $TUE_DIR/installer/scripts/tue-get-dep $@
    else
        echo "[tue-get] Unknown command: '$cmd'"
        return 1
    fi
}

function _tue-get
{
    local cur=${COMP_WORDS[COMP_CWORD]}
    local prev=${COMP_WORDS[COMP_CWORD-1]}

    if [ $COMP_CWORD -eq 1 ]; then
        COMPREPLY=( $(compgen -W "dep install update remove list-installed" -- $cur) )
    else
        cmd=${COMP_WORDS[1]}
        if [[ $cmd == "install" ]]
        then
            COMPREPLY=( $(compgen -W "`ls $TUE_DIR/installer/targets`" -- $cur) )        
        elif [[ $cmd == "dep" ]]
        then
            COMPREPLY=( $(compgen -W "`ls $TUE_ENV_DIR/.env/dependencies`" -- $cur) ) 
        elif [[ $cmd == "update" ]]
        then
            COMPREPLY=( $(compgen -W "`ls $TUE_ENV_DIR/.env/dependencies`" -- $cur) ) 
        elif [[ $cmd == "remove" ]]
        then
            COMPREPLY=( $(compgen -W "`ls $TUE_ENV_DIR/.env/installed`" -- $cur) )  
        else
            COMREPLY=""
        fi
    fi
}
complete -F _tue-get tue-get

# ----------------------------------------------------------------------------------------------------
#                                             TUE-BRANCH
# ----------------------------------------------------------------------------------------------------

function tue-branch
{
    if [ -z "$1" ]
    then
        echo """Switches all packages to the given branch, if such a branch exists in that package. Usage:

    tue-branch BRANCH-NAME

"""
        return 1
    fi

    local branch=$1

    fs=`ls $TUE_SYSTEM_DIR/src`
    for pkg in $fs
    do
        pkg_dir=$TUE_SYSTEM_DIR/src/$pkg

        if [ -d $pkg_dir ]
        then
            local memd=$PWD
            cd $pkg_dir
            test_branch=$(git branch --list $branch 2>&1)
            if [ $? -eq 0 ] && [ "$test_branch" ]
            then
                local current_branch=`git rev-parse --abbrev-ref HEAD`
                if [[ "$current_branch" == "$branch" ]]
                then
                    echo -e "\033[1m$pkg\033[0m: Already on branch $branch"
                else
                    res=$(git checkout $branch 2>&1)
                    if [ $? -eq 0 ]                
                    then
                        echo -e "\033[1m$pkg\033[0m: checked-out $branch"
                    else
                        echo ""
                        echo -e "    \033[1m$pkg\033[0m"
                        echo "--------------------------------------------------"
                        echo -e "\033[38;5;1m$res\033[0m"
                        echo "--------------------------------------------------"
                    fi
                fi
            fi
            cd $memd
        fi
    done
}

# ----------------------------------------------------------------------------------------------------
#                                              TUE-ENV
# ----------------------------------------------------------------------------------------------------

function tue-env
{
    if [ -z "$1" ]
    then
        echo """tue-env is a tool for switching between different installation environments.

    Usage: tue-env COMMAND [ARG1 ARG2 ...]

    Possible commands:

        init           - Initializes new environment
        remove         - Removes an existing enviroment (no data is lost)
        switch         - Switch to a different environment
        config         - Configures current environment
        set-default    - Set default environment
        list           - List all possible environments
        list-current   - Shows current environment
        cd             - Changes directory to environment directory
"""
        return 1
    fi

    cmd=$1
    shift

    # Make sure the correct directories are there
    mkdir -p $TUE_DIR/user/envs

    if [[ $cmd == "init" ]]
    then
        if [ -z "$1" ]
        then
            echo "Usage: tue-env init NAME [ DIRECTORY ]"
            return 1
        fi

        local dir=$PWD   # default directory is current directory
        [ -z "$2" ] || dir=$2

        # TODO: make dir absolute

        if [ -f $TUE_DIR/user/envs/$1 ]
        then
            echo "[tue-env] Environment '$1' already exists"
            return 1
        fi

        if [ -d $dir/.env ]
        then
            echo "[tue-env] Directory '$dir' is already an environment directory."
            return 1
        fi

        echo "$dir" > $TUE_DIR/user/envs/$1
        mkdir -p $dir/.env
    elif [[ $cmd == "remove" ]]
    then
        if [ -z "$1" ]
        then
            echo "Usage: tue-env remove ENVIRONMENT"
            return 1
        fi

        if [ ! -f $TUE_DIR/user/envs/$1 ]
        then
            echo "[tue-env] No such environment: '$1'."
            return 1
        fi

        rm $TUE_DIR/user/envs/$1
    elif [[ $cmd == "switch" ]]
    then
        if [ -z "$1" ]
        then
            echo "Usage: tue-env switch ENVIRONMENT"
            return 1
        fi

        if [ ! -f $TUE_DIR/user/envs/$1 ]
        then
            echo "[tue-env] No such environment: '$1'."
            return 1
        fi

        export TUE_ENV=$1
        export TUE_ENV_DIR=`cat $TUE_DIR/user/envs/$1`
        
        source ~/.bashrc

    elif [[ $cmd == "set-default" ]]
    then
        if [ -z "$1" ]
        then
            echo "Usage: tue-env set-default ENVIRONMENT"
            return 1
        fi

        mkdir -p $TUE_DIR/user/config
        echo "$1" > $TUE_DIR/user/config/default_env

    elif [[ $cmd == "config" ]]
    then
        mkdir -p user_setup.bash    
        vim $TUE_ENV_DIR/.env/setup/user_setup.bash

    elif [[ $cmd == "cd" ]]
    then
        local env=$1
        [ -n "$env" ] || env=$TUE_ENV

        local dir=`cat $TUE_DIR/user/envs/$env`
        cd $dir

    elif [[ $cmd == "list" ]]
    then
        [ -d $TUE_DIR/user/envs ] || return 0

        for env in `ls $TUE_DIR/user/envs`
        do
            echo $env
        done
    elif [[ $cmd == "list-current" ]]
    then
        echo $TUE_ENV
    else
        echo "[tue-env] Unknown command: '$cmd'"
        return 1
    fi
}

function _tue-env
{
    local cur=${COMP_WORDS[COMP_CWORD]}
    local prev=${COMP_WORDS[COMP_CWORD-1]}

    if [ $COMP_CWORD -eq 1 ]; then
        COMPREPLY=( $(compgen -W "init list switch list-current remove cd set-default config" -- $cur) )
    else
        cmd=${COMP_WORDS[1]}
        if [[ $cmd == "switch" ]] || [[ $cmd == "remove" ]] || [[ $cmd == "cd" ]] || [[ $cmd == "set-default" ]]
        then
            if [ $COMP_CWORD -eq 2 ]
            then
                local envs=
                [ -d $TUE_DIR/user/envs ] && envs=`ls $TUE_DIR/user/envs`
                COMPREPLY=( $(compgen -W "$envs" -- $cur) )        
            fi
        fi
    fi
}
complete -F _tue-env tue-env

# ----------------------------------------------------------------------------------------------------

source $TUE_DIR/setup/tue-data.bash

