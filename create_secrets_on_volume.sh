#!/bin/bash
. .env
PDIR="./tx-monitor-image/config/shared"
CDIR=$(pwd)
K_VOL="tx_monitor_keys_vol1"
I_VOL="tx_monitor_info_vol1"



if [[ "${1}" == "" ]];then
	echo "missing use case, exiting"
	exit
fi

if [[ ! -f ".${1}.info" ]] ; then
	echo "missing file .${1}.info in current directory which is required for use case $1,exiting "
	exit
fi

M_KEYS=$(docker volume inspect ${K_VOL} |jq -r '.[].Options.device')
M_INFO=$(docker volume inspect ${I_VOL} |jq -r '.[].Options.device')

echo $M_KEYS 
echo $M_INFO


export TX_AGEDIR_KEYS=${M_KEYS}
export TX_AGEDIR_INFO=${M_INFO}
export TX_SHARED_GROUP_NAME=${TX_SHARED_GROUP_NAME}
export TX_INFO_FILE_LOCATION=${CDIR}

docker volume inspect ${K_VOL}  -f "{{json .Options.device }}"
retVal=$?

if [[ "$retVal" -eq 0 ]];then
	cd ${PDIR}
	echo "ok"
	./shared_gen_info.sh ${1}
else
	echo "wth"
fi

cd ${CDIR}

