#!/bin/bash
#set -x
. shared_logging.sh

if [[ -z "$1" || -z "$2" ]]; then
    logerr "exit no action: specify use case as first parameter and key as second parameter"
    exit 1
fi

USE_CASE=${1}
KEYDIR=${TX_AGEDIR_KEYS}/.${USE_CASE}
INFDIR=${TX_AGEDIR_INFO}/.${USE_CASE}

KEYFILE=${USE_CASE}.age
INFILE=.${USE_CASE}

if [[ ! -f "${KEYDIR}/${KEYFILE}" || ! -f "${INFDIR}/.${USE_CASE}" ]]; then
    logerr "missing age key or encrypted password file - exit"
    exit 2
fi

age -d -i ${KEYDIR}/${KEYFILE}  ${INFDIR}/${INFILE}|jq -r ''".$2"'' |sed 's/^"//;s/"$//'
