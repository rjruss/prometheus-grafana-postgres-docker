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
CERT_NAME="grafana"
CERT_DB_LOCATION="${HOME}/.postgresql"
CERT_DB_NAME="${TX_POSTGRES_USER}"

#
export CONFIG_FILE=/srv/custom/graf.ini
export HOMEPATH=/srv/grafana-v${TX_APP_GRAFANA_VERSION}

INST_LOCFILE=${CONFIG_FILE}

check_step_ca () {

        #check_step_ca ${number_of_loops} ${sleep duration}
        for (( i=1; i<=${1}; i++ )); do
                curl -sk  ${TX_STEP_HOST}/roots.pem -o stepCA.pem
                retVal=$?
                if [[ $retVal -eq 0 ]];then
                        let stepca_cdur=$(step ca provisioner list --ca-url=${TX_STEP_HOST} --root=./stepCA.pem |jq -r '.[0].claims.maxTLSCertDuration | split("h")[0]')
                        let app_cdur=$(echo $TX_GRAFANA_CERT_DUR |sed "s/h//")
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
	step ca certificate ${TX_CONTAINER_NAME} ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${TX_GRAFANA_CERT_DUR} --san ${TX_CONTAINER_NAME} --san $HOST_FQDN  --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
	#db user connection certificate
	step ca certificate ${CERT_DB_NAME} ${CERT_DB_LOCATION}/${CERT_DB_NAME}.crt ${CERT_DB_LOCATION}/${CERT_DB_NAME}.key  --not-after ${TX_GRAFANA_CERT_DUR} --san ${CERT_DB_NAME} --san $HOST_FQDN  --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)


}

renew () {

	loginfo "checking certificate for renewal"
        step certificate verify ${CERT_LOCATION}/${CERT_NAME}.crt  --roots ${STEPPATH}/certs/root_ca.crt  --host=${TX_CONTAINER_NAME}
        retVal=$?
        if [ $retVal -eq 0 ];then
                loginfo "renew ${CERT_NAME} certificate"
                step ca renew -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
                step ca renew -f ${CERT_DB_LOCATION}/${CERT_DB_NAME}.crt ${CERT_DB_LOCATION}/${CERT_DB_NAME}.key
        else
                logwarn "${CERT_NAME} certificate expired or other error "
                loginfo "recreate ${CERT_NAME} certificate"
                rm -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
                rm -r ${CERT_DB_LOCATION}/${CERT_DB_NAME}.crt ${CERT_DB_LOCATION}/${CERT_DB_NAME}.key
		step ca certificate ${TX_CONTAINER_NAME} ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${TX_GRAFANA_CERT_DUR} --san ${TX_CONTAINER_NAME} --san $HOST_FQDN  --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
		#db user connection certificate
		step ca certificate ${CERT_DB_NAME} ${CERT_DB_LOCATION}/${CERT_DB_NAME}.crt ${CERT_DB_LOCATION}/${CERT_DB_NAME}.key  --not-after ${TX_GRAFANA_CERT_DUR} --san ${CERT_DB_NAME} --san $HOST_FQDN  --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
                cp -p ${STEPPATH}/certs/root_ca.crt ${CERT_DB_LOCATION}/root.crt
        fi



}

config_file () {

	loginfo "config_file"
	#TX_GRAFANA_PORT
cat << EOF > ${CONFIG_FILE}
[server]
http_addr =
http_port = ${TX_GRAFANA_PORT}
domain = ${TX_CONTAINER_NAME}
root_url = https://${HOST_FQDN}:${TX_GRAFANA_PORT}
cert_key = ${CERT_LOCATION}/${CERT_NAME}.key
cert_file = ${CERT_LOCATION}/${CERT_NAME}.crt
root_ca_cert = ${STEPPATH}/certs/root_ca.crt
enforce_domain = False
protocol = https
[database]
type=postgres
host=${TX_DB_HOST}:${TX_DB_PORT}
name=${TX_POSTGRES_DB}
user=${TX_POSTGRES_USER}
password="-"
ssl_mode=require
ca_cert_path=${CERT_DB_LOCATION}/root.crt
client_key_path=${CERT_DB_LOCATION}/${CERT_DB_NAME}.key
client_cert_path=${CERT_DB_LOCATION}/${CERT_DB_NAME}.crt
server_cert_name=${TX_POSTGRES_USER}
EOF


}


startup () {

	loginfo "startup"
	${HOMEPATH}/bin/grafana server --homepath=${HOMEPATH}  --config=${CONFIG_FILE}  > /proc/1/fd/1 2>/proc/1/fd/2 &

}

post_startup_init () {

	loginfo "post start initialisation actions"
	 set +x; ${HOMEPATH}/bin/grafana cli  --homepath=${HOMEPATH} --config=${CONFIG_FILE}  admin reset-admin-password `shared_get_info.sh GRAFANA GRAFANA_PW`; set -x

}

stopapp () {

	loginfo "stopping "
	pkill -P $$

}

shutdown_stopapp () {

	stopapp
	exit 0

}

reload_config () {

	loginfo "reload config"
	kill -HUP $$

}



andcheck () {

	loginfo "test"
	        while true
        do
                step certificate needs-renewal --expires-in ${TX_GRAFANA_EXP_CHECK}  ${CERT_LOCATION}/${CERT_NAME}.crt
                retVal=$?
                if [ $retVal -eq 0 ];then
                        renew
                        loginfo "certificates refreshed "
			reload_config
                        #pkill -P $$
                        #startup
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
                sleep 25
                post_startup_init
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

