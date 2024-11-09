#!/bin/bash
. .env
if [[ "${1}" == "" ]];then
	echo "provide the new app name"
	exit 1
fi

ask_new_input () {
	ask=""
	msg="$1"  
    while true; do
        read -p "$msg :" ask  
        echo "You entered: $ask" >&2
        read -p "Is this correct? (y/n): " confirm
        if [[ $confirm == [Yy] ]]; then
            break  
        else
            echo "update $msg." >&2
        fi
    done

    echo "$ask"
}

UPPER1=$(echo ${1} | tr '[:lower:]' '[:upper:]')


UPDATE_STEP_HOST=$(ask_new_input "enter STEP host URL e.g. https://stephost.domain.org:9000"| sed "s/https:\/\///")
sed "s/\[\&REPLACE_STEP_HOST\&\]/${UPDATE_STEP_HOST}/g" TEMPLATE.env >.env

HOST_APP=$(ask_new_input "enter suffix of hostname it will be added to base host e.g. ${BASE_HOST}suffix")
echo "${UPPER1}_HOST=\${BASE_HOST}${HOST_APP}" >>.env

APP_VER=$(ask_new_input "enter new app version to use")
echo "TX_APP_${UPPER1}_VERSION=${APP_VER}" >>.env

echo "copying .env to TEMPLATE.env"
cp .env TEMPLATE.env

echo "update compose and dockerfile"
sed "s/\[\&replace_lower_app_name\&\]/${1}/g;s/\[\&REPLACE_UPPER_APP_NAME\&\]/${UPPER1}/g" template_compose_file > tx-monitor-${1}-build-extracted-compose.yml
sed "s/\[\&REPLACE-APP-NAME\&\]/${UPPER1}/g;s/\[\&replace-user-name\&\]/${1}1/g;s/\[\&replace-app-name\&\]/${1}/g"  template-build-split-docker > tx-monitor-${1}-build-split-docker

echo "setup app template"
mkdir -p tx-monitor-${1}/config
sed "s/\[\&replace_lower_app_name\&\]/${1}/g;s/\[\&REPLACE_UPPER_APP_NAME\&\]/${UPPER1}/g" template_start_script.sh > tx-monitor-${1}/config/start-${1}.sh
#cp template_start_script.sh  tx-monitor-${1}/config/start-${1}.sh

chown ${LOCAL_DOCKER_USER}:${TX_SHARED_GROUP_NAME} tx-monitor-${1}-build-split-docker tx-monitor-${1}-build-extracted-compose.yml
chown -R ${LOCAL_DOCKER_USER} tx-monitor-${1}
chgrp -R ${TX_SHARED_GROUP_NAME}  tx-monitor-${1}

echo
echo "check config and settings and then run these scripts"
echo "create_docker_multi_volumes.sh  # create docker volumes"
echo "create_docker_multi_network.sh  # create docker networks"
echo "create_secrets_on_volume.sh     # to create the passwords for the app"
echo
while read i; do
	echo "check dependancies in $i - ignore any errors below as command checks even if there are no dependancies"
	yq '.services[].depends_on' $i
done < <( ls *extracted-compose.yml)
