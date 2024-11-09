#!/bin/bash

set -x
. shared_logging.sh
###############################
## ACtion - _CHANGE_TO_REQUIRED_APP_CERT_DUR_VARIABLE to the required Variable
## ACtion - Update INST_LOCFILE & CERT_LOCATION
#################################
HOST_FQDN=`hostname -f`

HN=`hostname -f`
#TX_CONTAINER_NAME
CERT_LOCATION="${HOME}/cert"
CERT_NAME="node_exporter"

export WEB_CONFIG_FILE="${TX_MONITOR_DIR}/custom/web-config.yml"

INST_LOCFILE="${WEB_CONFIG_FILE}"

check_step_ca () {

        #check_step_ca ${number_of_loops} ${sleep duration}
        for (( i=1; i<=${1}; i++ )); do
                curl -sk  ${TX_STEP_HOST}/roots.pem -o stepCA.pem
                retVal=$?
                if [[ $retVal -eq 0 ]];then
                        let stepca_cdur=$(step ca provisioner list --ca-url=${TX_STEP_HOST} --root=./stepCA.pem |jq -r '.[0].claims.maxTLSCertDuration | split("h")[0]')
                        let app_cdur=$(echo $TX_NODE_EXPORTER_CERT_DUR |sed "s/h//")
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
	step ca certificate ${TX_CONTAINER_NAME} ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${TX_NODE_EXPORTER_CERT_DUR} --san ${TX_CONTAINER_NAME} --san $HOST_FQDN --san ${MY_HOST_FQDN} --san localhost --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
	#db user connection certificate


}

renew () {

        loginfo "checking certificate for renewal"
        step certificate verify ${CERT_LOCATION}/${CERT_NAME}.crt  --roots ${STEPPATH}/certs/root_ca.crt  --host=${TX_CONTAINER_NAME}
        retVal=$?
        if [ $retVal -eq 0 ];then
                loginfo "renew ${CERT_NAME} certificate"
                step ca renew -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
        else
                logwarn "${CERT_NAME} certificate expired or other error "
                loginfo "recreate ${CERT_NAME} certificate"
                rm -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
		step ca certificate ${TX_CONTAINER_NAME} ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${TX_NODE_EXPORTER_CERT_DUR} --san ${TX_CONTAINER_NAME} --san $HOST_FQDN --san ${MY_HOST_FQDN} --san localhost --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
        fi


}

config_file () {

cat << EOF > ${WEB_CONFIG_FILE}
tls_server_config:
#  client_auth_type: "RequireAnyClientCert"
#  client_auth_type: "NoClientCert"
  client_auth_type: "RequestClientCert"
  client_ca_file: ${STEPPATH}/certs/root_ca.crt
  cert_file: ${CERT_LOCATION}/${CERT_NAME}.crt
  key_file: ${CERT_LOCATION}/${CERT_NAME}.key
EOF


}


startup () {

        loginfo "starting"
        ${TX_MONITOR_DIR}/node_exporter/node_exporter --web.config.file=${WEB_CONFIG_FILE} --web.listen-address=:${TX_NODE_EXPORTER_PORT} --path.rootfs=/host &


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

        loginfo "sleeping and checking certificate expiry"
        while true
        do
                step certificate needs-renewal --expires-in ${TX_NODE_EXPORTER_CERT_DUR}  ${CERT_LOCATION}/${CERT_NAME}.crt
                retVal=$?
                if [ $retVal -eq 0 ];then
                        renew
                        loginfo "certificates refreshed node_exporter picks it up automatically"
                fi
        sleep 30m
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

