#!/bin/bash

log() {
    sev=$1
    shift
    msg="$@"
    ts=$(date +"%Y/%m/%d %H:%M:%S")
    echo -e "$ts : $sev : $msg"
}

loginfo() {
    log "INFO" "$@"
}

logwarn() {
    log "${TX_BOLD}WARNING${TX_RESET}" "$@"
}

logerr() {
    log "${TX_BOLD}ERROR${TX_RESET}" "$@"
}
