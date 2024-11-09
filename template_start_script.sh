#!/bin/bash

set -x
. shared_logging.sh
###############################
## ACtion - _CHANGE_TO_REQUIRED_APP_CERT_DUR_VARIABLE to the required Variable
## ACtion - Update INST_LOCFILE & CERT_LOCATION
#################################
HOST_FQDN=`hostname -f`

INST_LOCFILE="{file or process to check that APP is initialised}"
HN=`hostname -f`
#TX_CONTAINER_NAME
CERT_LOCATION="./cert"
CERT_NAME="[&replace_lower_app_name&]"
CERT_DB_LOCATION="./.postgresql"
CERT_DB_NAME="${TX_POSTGRES_USER}"

check_step_ca () {

        #check_step_ca ${number_of_loops} ${sleep duration}
        for (( i=1; i<=${1}; i++ )); do
                curl -sk  ${TX_STEP_HOST}/roots.pem -o stepCA.pem
                retVal=$?
                if [[ $retVal -eq 0 ]];then
                        let stepca_cdur=$(step ca provisioner list --ca-url=${TX_STEP_HOST} --root=./stepCA.pem |jq -r '.[0].claims.maxTLSCertDuration | split("h")[0]')
                        let app_cdur=$(echo $TX_[&REPLACE_UPPER_APP_NAME&]_CERT_DUR |sed "s/h//")
                        if [[ "$app_cdur" -le "$stepca_cdur" ]]; then
                                return 0
                                else
                                logwarn "Step is available but the max certificate expiry is not set correctly, post script wants $app_cdur waiting for step as its currently $stepca_cdur: attempt $i / ${1}"
                        fi
                fi
                sleep ${2}
        done

        return 1

}


initialise_app () {

	loginfo "initial setup of application"
        FP=$(step certificate fingerprint stepCA.pem)
        step ca bootstrap --ca-url ${TX_STEP_HOST} --fingerprint ${FP}
	#app server certificate
	step ca certificate ${TX_CONTAINER_NAME} ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${TX_[&REPLACE_UPPER_APP_NAME&]_CERT_DUR} --san ${TX_CONTAINER_NAME} --san $HOST_FQDN  --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
	#db user connection certificate
	step ca certificate ${CERT_DB_NAME} ${CERT_DB_LOCATION}/${CERT_DB_NAME}.crt ${CERT_DB_LOCATION}/${CERT_DB_NAME}.key  --not-after ${TX_[&REPLACE_UPPER_APP_NAME&]_CERT_DUR} --san ${CERT_DB_NAME} --san $HOST_FQDN  --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)


}

renew () {

	loginfo "renew"

}

config_file () {

	loginfo "config_file"

}


startup () {

	loginfo "startup"

}

post_startup_init () {

	loginfo "post start initialisation actions"

}

stopapp () {

	loginfo "stopping "

}

shutdown_stopapp () {

	stopapp
	exit 0

}


andcheck () {

	loginfo "test"

	stopapp
	renew
	startup

}


trap shutdown_stopapp TERM INT

if [[ ! -f ${INST_LOCFILE} ]];then
        if check_step_ca 2 10; then
                loginfo "setup TX_APP"
                initialise_app
                config_file
                startup
                post_startup_init
                sleep 25
                andcheck
        else
                logerr "Exiting setup as step ca cant be contacted"
        fi


else
        
        if check_step_ca 2 10; then
                loginfo "Renew certificate and startup TX_APP"
                renew
                startup
                andcheck
        else
                logerr "Failure to connect to step-ca - cant renew certificates but starting TX_APP and certificates may cause issues "
                startup
                andcheck      
        fi

fi



tail -f /dev/null

