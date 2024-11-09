#!/bin/bash

set -x
. shared_logging.sh
###############################
## ACtion - _CHANGE_TO_REQUIRED_APP_CERT_DUR_VARIABLE to the required Variable
## ACtion - Update INST_LOCFILE & CERT_LOCATION
#################################
export HOST_FQDN=`hostname -f`

#TX_CONTAINER_NAME
export CERT_LOCATION="${HOME}/cert"
export CERT_NAME="prometheus"
CERT_DB_LOCATION="./.postgresql"
CERT_DB_NAME="${TX_POSTGRES_USER}"

export CONF_DIR=${TX_MONITOR_DIR}/custom
export PROM_CONFIG_FILE=${CONF_DIR}/prom.yml
export ALER_CONFIG_FILE=${CONF_DIR}/alert.yml
export WEB_CONFIG_FILE=${CONF_DIR}/web-config.yml
export AMTOOL_FILE=${CONF_DIR}/amtoolhttp.yml
export LOCAL_DOMAIN_NAME=$(hostname -d)


INST_LOCFILE=${PROM_CONFIG_FILE}

check_step_ca () {

        #check_step_ca ${number_of_loops} ${sleep duration}
        for (( i=1; i<=${1}; i++ )); do
                curl -sk  ${TX_STEP_HOST}/roots.pem -o stepCA.pem
                retVal=$?
                if [[ $retVal -eq 0 ]];then
                        let stepca_cdur=$(step ca provisioner list --ca-url=${TX_STEP_HOST} --root=./stepCA.pem |jq -r '.[0].claims.maxTLSCertDuration | split("h")[0]')
                        let app_cdur=$(echo $TX_PROMETHEUS_CERT_DUR |sed "s/h//")
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
	step ca certificate ${TX_CONTAINER_NAME} ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${TX_PROMETHEUS_CERT_DUR} --san ${TX_CONTAINER_NAME} --san $HOST_FQDN --san localhost --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
	#db user connection certificate
#	step ca certificate ${CERT_DB_NAME} ${CERT_DB_LOCATION}/${CERT_DB_NAME}.crt ${CERT_DB_LOCATION}/${CERT_DB_NAME}.key  --not-after ${TX_PROMETHEUS_CERT_DUR} --san ${CERT_DB_NAME} --san $HOST_FQDN  --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
#       cp -p ${STEPPATH}/certs/root_ca.crt ${CERT_DB_LOCATION}/root.crt


}

renew () {

        loginfo "checking certificate for renewal"
        step certificate verify ${CERT_LOCATION}/${CERT_NAME}.crt  --roots ${STEPPATH}/certs/root_ca.crt  --host=${TX_CONTAINER_NAME}
        retVal=$?
        if [ $retVal -eq 0 ];then
                loginfo "renew ${CERT_NAME} certificate"
                step ca renew -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
#                step ca renew -f ${CERT_DB_LOCATION}/${CERT_DB_NAME}.crt ${CERT_DB_LOCATION}/${CERT_DB_NAME}.key
        else
                logwarn "${CERT_NAME} certificate expired or other error "
                loginfo "recreate ${CERT_NAME} certificate"
                rm -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
#                rm -r ${CERT_DB_LOCATION}/${CERT_DB_NAME}.crt ${CERT_DB_LOCATION}/${CERT_DB_NAME}.key
		step ca certificate ${TX_CONTAINER_NAME} ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${TX_PROMETHEUS_CERT_DUR} --san ${TX_CONTAINER_NAME} --san $HOST_FQDN --san localhost --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
                #db user connection certificate
#                step ca certificate ${CERT_DB_NAME} ${CERT_DB_LOCATION}/${CERT_DB_NAME}.crt ${CERT_DB_LOCATION}/${CERT_DB_NAME}.key  --not-after ${TX_PROMETHEUS_CERT_DUR} --san ${CERT_DB_NAME} --san $HOST_FQDN  --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
#                cp -p ${STEPPATH}/certs/root_ca.crt ${CERT_DB_LOCATION}/root.crt
        fi





}

config_file () {

	loginfo "config_file"
	. ${HOME}/startup/setup_prom_config.sh

}


startup () {

	loginfo "startup"
        loginfo "starting"
        ${TX_MONITOR_DIR}/prometheus/prometheus --config.file=${PROM_CONFIG_FILE} --web.config.file=${WEB_CONFIG_FILE} --web.external-url=https://${HOST_FQDN}:${TX_PROMETHEUS_PORT} --web.listen-address=${HOST_FQDN}:${TX_PROMETHEUS_PORT} &
        ${TX_MONITOR_DIR}/alertmanager/alertmanager --config.file=${ALER_CONFIG_FILE} --web.config.file=${WEB_CONFIG_FILE} --web.listen-address=${HOST_FQDN}:${TX_ALERTMANAGER_PORT} --cluster.listen-address= &


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

reload_config () {

        loginfo "prometheus should pick up new certs by default but using reload config for general refresh"
        kill -HUP $$

}


andcheck () {

	loginfo "sleeping and checking certificate expiry"
        while true
        do
                step certificate needs-renewal --expires-in ${TX_PROMETHEUS_EXP_CHECK}  ${CERT_LOCATION}/${CERT_NAME}.crt
                retVal=$?
                if [ $retVal -eq 0 ];then
                        renew
                        reload_config
                fi
        sleep 10m
        done



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

