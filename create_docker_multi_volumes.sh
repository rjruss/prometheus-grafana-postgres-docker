#!/bin/bash
#set -x


if ! command -v yq &> /dev/null ;then
    echo "yq could not be found"
    exit 1
fi
. .env

DOCKER_SUFFIX="extracted-compose.yml"
DOCKER_VOLUME_SUFFIX="vol1"

#LOCAL_DOCKER_VOLUME_DIR
if [[ ! -d "${LOCAL_DOCKER_VOLUME_DIR}" ]];then
	echo "Chosen docker directory does not exist - please create and run again"
	exit
fi

#yq '.volumes | keys' robert_compose.yml|grep "vol1" |sed "s/- //" |while read i
while read DOCKER_FILE ;do
	echo "processing ${DOCKER_FILE}"
	yq '.volumes | keys | .[]' ${DOCKER_FILE} |grep "${DOCKER_VOLUME_SUFFIX}" |while read i
	do

		echo "  volume $i"
		CHECKVOL=$(docker volume inspect ${i} 2>/dev/null|jq -r '.[]|.Options.device')
		if [[ "${CHECKVOL}" == "" ]];then
			mkdir -p $LOCAL_DOCKER_VOLUME_DIR/${i}
			retVal=$?
			if [ $retVal -ne 0 ];then
				echo "error creating directory for volume-  exiting"
				exit 1
			fi
			chgrp -R ${TX_SHARED_GROUP_NAME} $LOCAL_DOCKER_VOLUME_DIR/${i}
			chmod g+w  $LOCAL_DOCKER_VOLUME_DIR/${i}
			docker volume create  --driver local -o o=bind -o type=none -o device=$LOCAL_DOCKER_VOLUME_DIR/${i} ${i}
			ls -ld $LOCAL_DOCKER_VOLUME_DIR/${i}
		else
			echo "  error found $i already exists, no further action"
		fi

	done
echo
done < <(ls *${DOCKER_SUFFIX})
