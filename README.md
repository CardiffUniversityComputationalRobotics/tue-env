# cucr-env

[![CI](https://github.com/tue-robotics/tue-env/actions/workflows/main.yml/badge.svg)](https://github.com/tue-robotics/tue-env/actions/workflows/main.yml)

Package manager that can be used to install (ROS) dependencies

## Installation

### Ubuntu 20.04/22.04

Standard cucr-env installation with targets from [cucr-env-targets](https://github.com/CardiffUniversityComputationalRobotics/tue-env-targets)

#### Installing the cucr-env

1. Bootstrap the package manager

   ```bash
   source <(wget -O - https://raw.githubusercontent.com/CardiffUniversityComputationalRobotics/tue-env/cucr/installer/bootstrap_cucr.bash)  # for default ROS1
   # Or
   source <(wget -O - https://raw.githubusercontent.com/CardiffUniversityComputationalRobotics/tue-env/cucr/installer/bootstrap_cucr.bash) --ros-version=2  # for ROS2
   ```

2. Install target(s)

   ```bash
   cucr-get install [package_name]
   ```

3. Build sources

   ```bash
   cucr-make
   source ~/.bashrc  # Or open a new terminal
   ```

### Customization

A customized targets repository can be setup with this package manager (currently only one git repository is supported). If `cucr-env` is already installed, to set up the targets repository run:

```bash
cucr-env init-targets [ENVIRONMENT] <targets_repo_git_url>
```

This will do the same as running the commands separately:

```bash
cucr-env init ENVIRONMENT [DIRECTORY] # Will not result in an environment being loaded. Unless one was already loaded before
cucr-env init-targets [ENVIRONMENT] <targets_repo_git_url> # The environment arg is required, when no environment is loaded
```

else first setup `cucr-env` by manually following the procedure in the bootstrap
script.

You can also set the targets repository in the initial setup by providing it as an argument of the bootstrap script.
Add `--targets-repo=<targets_repo_git_url>` as argument, this can be any type of url supported by git.

When a targets repository is already initialized. It can be switched by running the same `init-targets` command.
This will rename the old targets folder with a timestamp and clone the new targets repo in place.

#### Add SSH key to GitHub to gain access to this repository

Add the public part of your ssh-key (`cat ~/.ssh/<KEY_NAME>.pub`, where `<KEY_NAME>` is the name of your ssh-key) to GitHub > Settings > SSH and GPG keys and `New SSH key`

To generate a new ssh keypair:

```bash
sudo apt-get install ssh
ssh-keygen -o -a 100 -t ed25519
cat ~/.ssh/<KEY_NAME>.pub
```

## Usage

With `cucr-get` you can install various targets which mostly are ros packages.
The list of packages can be seen [here](https://github.com/CardiffUniversityComputationalRobotics/tue-env-targets).

```bash
cucr-get install <TARGET_NAME>
```

For example, to install a default development installation for working with
CUCR robots, run the following command:

```bash
cucr-get install cucr-dev
```

**Note:** Any ROS package which has a source installation must be built. In the
current implementation of `cucr-get` this doesn't happen automatically. However,
we provide an alias to `catkin build`/`colcon build` as `cucr-make` which would build the
`cucr-env` workspace.

Upon executing the installation instructions mentioned in the previous section, `~/.cucr/setup.bash` is automatically added in `.bashrc`. Sourcing `.bashrc` would make `cucr-env` available to the bash session.

## Different environments

To isolate builds you can use different environments. Each environment will contain a different copy of the repositories used. These environments can also be useful to separate ROS1 from ROS2 installs.

To initialise a new environment (for example the Pico robot):

```bash
mkdir ~/ros/pico && cucr-env init pico ~/ros/pico
```

Now to switch to this environment and install a package you can:

```bash
cucr-env switch pico
cucr-get install ros-pico
```

Or use `cucr-env set-default` if you want this to be de default.

## Guidelines on creating a new target

The targets directory is located at `.env/targets` relative to the root of the environment directory. The target directory of each environment can be accessed by:

```bash
cucr-env targets # Will change the directory to the targets directory of the current environment
# or
cucr-env targets <environment> # Will change the directory to the targets directory of the specified environment
```

The targets directory contains a list of targets. Each target is a directory with the name of the target.

A target can consist of the following files:

1. `install.yaml`
2. `install.bash`
3. `setup`
4. `.ci_ignore/.ci_ignore_bash/.ci_ignore_yaml`

Installation happens in the above order. First `install.yaml` is parsed and the
instructions in it are executed. Then `install.bash` is executed. This must have
commands/instructions that cannot be specified in the YAML file. Lastly, the
`setup` file is sourced in the bash environment by `setup.bash` of cucr-env.

Any target dependencies that can be specified in `install.yaml` as other targets
or installable packages must be specified there. They should not be moved to
`install.bash`as`cucr-env` has many controls in place to parse the YAML file.

Some (parts of) targets are not used for testing, but do take a long time
to install. Therefore, it is preferable to skip these (parts of) targets during CI.
To ignore an entire target in CI, add a `.ci_ignore` file to the target. To either
ignore the bash script or the yaml file add respectively `.ci_ignore_bash` or `.ci_ignore_yaml`.

### Naming conventions

Name of the target must start with `ros-` only if it is a `catkin`/`colcon` (ROS) package. It's `install.yaml` file must be in the format of [ROS target](#ros-package-install).

### Writing `install.yaml`

| Symbol | Convention                             |
|--------|----------------------------------------|
| []     | Alternate options                      |
| <>     | Input argument required with the field |

Some fields are mentioned to be optional.

Taking the above into account, the following combinations for `install.yaml` are possible:

#### ROS package install

1. From source

   ```yaml
   - type: ros
     source:
       type: git
       url: <Repository URL>
       sub-dir: <Sub directory of the repository> (Optional field)
       version: <Version to be installed> (Optional field)
   ```

2. From system

   ```yaml
   - type: ros
     source:
       type: system
       name: <Package name>
   ```

3. Depending on ROS distro

   ```yaml
   - type: ros
     default:
       source:
         type: system
         name: <Package name>
     melodic:
       source:
         type: git
         url: <Repository URL>
     noetic:
       source: null
   ```

Both ROS distro specific as default can be 'null'. Preferred usage is default for current and feature distributions and exceptions for old distributions.

#### Catkin package install

```yaml
- type: catkin
  source:
    type: git
    url: <Repository URL>
    sub-dir: <Sub directory of the repository> (Optional field)
    version: <Version to be installed> (Optional field)
```

This target type is similar to a ROS source target with only difference being a catkin package is independent of any ROS
dependencies and solely depends on catkin.

#### Target / System / PIP / PIP3 / PPA / Snap / Gem / DPKG / Empty

```yaml
- type: [target/system/pip/pip3/ppa/snap/gem/dpkg/empty]
  name: <Name of the candidate>
```

Depending on Ubuntu distribution:

```yaml
- type: [target/system/pip/pip3/ppa/snap/gem/dpkg/empty]
  xenial:
    name: [null/<Name of the candidate>]
  default:
    name: [null/<Name of the candidate>]
```

Both Ubuntu distribution specific as default can be 'null'. Preferred usage is default for current and feature distributions and exceptions for old distributions.

#### (Target / System / PIP / PIP3 / PPA / Snap / Gem)-now

The default installation method for targets of type `system`, `pip(2/3)`, `ppa` and `snap` is to collect all such targets in a list and install them simultaneously at the end of the `cucr-get install` procedure. To install such a dependency immediately for a specific target, use the target type as `X-now`:

```yaml
- type: [target/system/pip/pip3/ppa/snap/gem]-now
  name: <Name of the candidate>

- type: [target/system/pip/pip3/ppa/snap/gem/dpkg]
  name: <Name of the candidate>
```

`target-now` will install a target directly recursively. So also all its dependencies will be installed directly, by converting them from `XX` to `XX-now`. Except `ROS` and `DPKG` are excluded. ROS dependencies are excluded, because ROS packages should only be used at runtime, because it requires either a compilation and/or resourcing the workspace.
It is preferred to include these `-now` dependencies in `install.yaml`. Only use the corresponding bash function in `install.bash` if no other solution is possible.

#### GIT

```yaml
- type: git
  url: <url>
  path: [path/where/to/clone] (Optional field)
  version: [branch/commit/tag] (Optional field)
```

### Writing `install.bash`

The use of the following variables is prohibited in `install.bash`:

- `CUCR_APT_GET_UPDATED_FILE`
- `CUCR_INSTALL_*`
- `install_file`
- `now`
- `old_deps`
- `parent_target`
- `state_file`
- `state_file_now`
- `target`
- `target_processed`

#### Generic `cucr-install` functions

The following functions provided with `cucr-env` must be preferred over any
generally used methods of installing packages:

| Function Name                   | Description                                                                                                    |
|---------------------------------|----------------------------------------------------------------------------------------------------------------|
| `cucr-install-add-text`          | To add/replace text in a file with `sudo` taken into account                                                   |
| `cucr-install-apt-get-update`    | Make sure that during next `cucr-install-system-now` call `apt-get` is updated                                  |
| `cucr-install-cp`                | Analogous to `cp` but takes `sudo` into account and the source should be relative to target                    |
| `cucr-install-ln`                | Analogous to `ln -s` but takes `sudo` into account and the source should be relative to target or absolute     |
| `cucr-install-dpkg`              | To install a debian dpkg file                                                                                  |
| `cucr-install-git`               | To install a git repository                                                                                    |
| `cucr-install-pip`               | To add a python pip3 package to a list to be installed at the end                                              |
| `cucr-install-pip3`              | To add a python pip3 package to a list to be installed at the end                                              |
| `cucr-install-pip-now`           | To install python pip3 package, but ignores it if already installed                                            |
| `cucr-install-pip3-now`          | To install python pip3 package, but ignores it if already installed                                            |
| `cucr-install-ppa`               | To add one PPA/DEB to a list to be added with `apt-add-repository` at the end, before apt-get                  |
| `cucr-install-ppa-now`           | To add a PPA/DEB with `apt-add-repository`, use ^ inside of a DEB and spaces between items                     |
| `cucr-install-snap`              | To add a snap package to a list to be installed at the end                                                     |
| `cucr-install-snap-now`          | To install a snap                                                                                              |
| `cucr-install-gem`               | To add a gem package to a list to be installed at the end                                                      |
| `cucr-install-gem-now`           | To install a gem                                                                                               |
| `cucr-install-system`            | To add `deb` package to a list of packages to be installed at the end with `apt-get`                           |
| `cucr-install-system-now`        | To install `deb` packages with `apt-get` right away, but ignores it if already installed                       |
| `cucr-install-get-releases`      | To get a released asset from a github repository and place it in the requested directory                       |

The input arguments for each of the above-mentioned commands can be found by
simply executing the command in a bash session (provided cucr-env is correctly
installed).

A general remark about the order of preference of package repositories:

system > ppa > pip = pip3 > snap > gem > git > dpkg

#### Logging

The following logging functions can be used:

| Function Name         | Description                                                                                                                                                                                  |
|-----------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `tue-install-debug`   | Labeled print to the log file; Also prints to stdout when running `tue-get` with `--debug`                                                                                                   |
| `tue-install-info`    | Labeled print to log file and stdout; Also printed again to stdout at the end of `tue-get`                                                                                                   |
| `tue-install-warning` | Similar to `tue-install-info`, but prints in blinking yellow                                                                                                                                 |
| `tue-install-error`   | Labeled print in red to log file and stdout and ends the execution of `tue-get`                                                                                                              |
| `tue-install-echo`    | Labeled echo to log file and stdout                                                                                                                                                          |
| `tue-install-tee`     | Plain print to log file and stdout                                                                                                                                                           |
| `tue-install-pipe`    | Executes the command with its arguments. Both stdout and stderr are captured and printed to the log file and stdout. The stderr is converted to red. Return code of the command is preserved |

## CI

### Adding SSH support to a repository

- For Travis CI with repository on GitLab, see [this](docs/CI_Travis_Setup.md)

## Bonus features

If the `BTRFS_SNAPSHOT` variable is set, a snapshot is made upon every install, update and remove call of `tue-get`.
