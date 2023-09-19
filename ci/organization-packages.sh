#! /usr/bin/env bash

for i in "$@"
do
    case $i in
        -o=* | --organization=* )
            ORGANIZATION="${i#*=}"
            ;;
        -t=* | --type=* )
            PACKAGE_TYPE="${i#*=}"
            ;;
        * )
            # unknown option
            if [[ -n "${i}" ]]  # Ignore empty arguments
            then
                echo -e "\e[35m\e[1mUnknown input argument '${i}'. Check CI .yml file\e[0m"
                exit 1
            fi
            ;;
    esac
    shift
done

echo -e "\e[35m\e[1mORGANIZATION = ${ORGANIZATION}\e[0m"
echo -e "\e[35m\e[1mPACKAGE_TYPE = ${PACKAGE_TYPE}\e[0m"

echo -e "\e[1mgh api -H \"Accept: application/vnd.github+json\" -H \"X-GitHub-Api-Version: 2022-11-28\" \"/orgs/${ORGANIZATION}/packages?package_type=${PACKAGE_TYPE}&per_page=100&page=1\" | jq -rc '.[].name'\e[0m"
output=$(gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "/orgs/${ORGANIZATION}/packages?package_type=${PACKAGE_TYPE}&per_page=100&page=1")
echo -e "return value: $?"
echo -e "output: ${output}"
packages=$(jq -rc '.[].name' <<< "${output}")
echo -e "packages:\n${packages}"
echo -e "\e[1mcurl -L -H \"Accept: application/vnd.github+json\" -H \"Authorization: Bearer \${GH_TOKEN}\" -H \"X-GitHub-Api-Version: 2022-11-28\" \"https://api.github.com/orgs/${ORGANIZATION}/packages?package_type=${PACKAGE_TYPE}&per_page=100&page=1\" | jq -rc '.[].name'\e[0m"
output=$(curl -L -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GH_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" "https://api.github.com/orgs/${ORGANIZATION}/packages?package_type=${PACKAGE_TYPE}&per_page=100&page=1")
echo -e "return value: $?"
echo -e "output: ${output}"
packages=$(jq -rc '.[].name' <<< "${output}")
echo -e "packages:\n${packages}"

echo -e "\e[35m\e[1mpackages:\e[0m"
for pkg in ${packages}
do
echo -e "\e[35m\e[1m  ${pkg}\e[0m"
done
for pkg in ${packages}
do
packages_list="${packages_list:+$packages_list, }'${pkg}'"
done
packages_list="[${packages_list}]"
