#!/bin/bash
#set -x
#

. shared_logging.sh

if [[ "${1}" == "" ]];then
        logerr "exit no action : specify use case - e.g. general / username / other"
        exit
fi

USE_CASE=${1}

if [[ "$TX_INFO_FILE_LOCATION" != "" ]];then
	USE_CASE_FILE=${TX_INFO_FILE_LOCATION}/.${USE_CASE}.info
else
	USE_CASE_FILE=./.${USE_CASE}.info
fi

KEYDIR=${TX_AGEDIR_KEYS}/.${USE_CASE}
INFDIR=${TX_AGEDIR_INFO}/.${USE_CASE}

mkdir -p ${KEYDIR}
mkdir -p ${INFDIR}

KEYFILE=${USE_CASE}.age
INFILE=.${USE_CASE}

if [ ! -f ${USE_CASE_FILE} ]
then
        logerr "create secret file ${USE_CASE_FILE} before proceeding"
        logerr "create in KEY VALUE pair"
        logerr "e.g. ADM_PW=YouKnowUNeed2ChangeThisButWillYou:)"
        exit
fi

 

if [ ! -f ${KEYDIR}/${KEYFILE} ]
then
        loginfo "creating age key"
        age-keygen > ${KEYDIR}/${KEYFILE}
        chmod 400 ${KEYDIR}/${KEYFILE}
else
        logwarn "overwriting age ${USE_CASE} key and info file"
	chmod 600 ${INFDIR}/${INFILE} ${KEYDIR}/${KEYFILE}
	age-keygen > ${KEYDIR}/${KEYFILE}
fi


declare -A jsonvals
counter=0
while read i; do
    key=$(echo "$i" | awk -F= '{print $1}')
    value=$(echo "$i" | awk -F= '{print $2}')
    jsonvals[$counter,0]="$key"
    jsonvals[$counter,1]="$value"
    ((counter++))
done < ${USE_CASE_FILE}

JSON_STRING="{"
for ((i=0; i<counter; i++)); do
    key="${jsonvals[$i,0]}"
    value="${jsonvals[$i,1]}"
    JSON_STRING+="\"$key\":$(jq -n --arg val "$value" '$val')"
    if [[ $i -lt $((counter-1)) ]]; then
        JSON_STRING+=","
    fi
done
JSON_STRING+="}"

loginfo "write out encrypted info to ${INFDIR} directory using key file in ${KEYDIR} : these need to be available in the container if using Docker"
echo "$JSON_STRING"  |age -e -i ${KEYDIR}/${KEYFILE} > ${INFDIR}/${INFILE}
chgrp ${TX_SHARED_GROUP_NAME} ${INFDIR}/${INFILE} ${KEYDIR}/${KEYFILE}

chmod 440 ${INFDIR}/${INFILE} ${KEYDIR}/${KEYFILE}
chmod 440 ${INFDIR}/${INFILE} ${KEYDIR}/${KEYFILE}

chgrp -R ${TX_SHARED_GROUP_NAME}  ${KEYDIR} ${INFDIR}
#chmod -R g+w ${KEYDIR} ${INFDIR}

ls -l $KEYDIR/$KEYFILE
loginfo $(stat -c "If using in a Dockerfile add user with uid %u and group gid %g" $KEYDIR/$KEYFILE)
