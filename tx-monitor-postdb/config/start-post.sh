#!/bin/bash

set -x
. shared_logging.sh

HOST_FQDN=`hostname -f`
INST_LOCFILE="${TX_MONITOR_APP_DIR}/postgresql.conf"
CERT_LOCATION=/home/postgres/cert
CERT_NAME="postdb"

STATUS_FILE="postgres_status"
echo "down" >${TX_DB_SHARED_LOCATION}/${STATUS_FILE}



check_step_ca () {
        #check_step_ca ${number_of_loops} ${sleep duration}
        for (( i=1; i<=${1}; i++ )); do
                curl -sk  ${TX_STEP_HOST}/roots.pem -o stepCA.pem
                retVal=$?
                if [[ $retVal -eq 0 ]];then
                        let stepca_cdur=$(step ca provisioner list --ca-url=${TX_STEP_HOST} --root=./stepCA.pem |jq -r '.[0].claims.maxTLSCertDuration | split("h")[0]')
                        let app_cdur=$(echo $TX_POST_CERT_DUR|sed "s/h//")
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
        #step ca certificate $HOST_FQDN ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key --san $HOST_FQDN  --provisioner-password-file  <(set +x;echo -n `shared_get_info STEP PW`;set -x)
        step ca certificate ${TX_CONTAINER_NAME} ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${TX_POST_CERT_DUR} --san ${TX_CONTAINER_NAME} --san $HOST_FQDN  --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
        #cat ${CERT_LOCATION}/${CERT_NAME}.crt /home/postgres/.step/certs/root_ca.crt  >> ${CERT_LOCATION}/postfullchain.crt

        set +x;POSTGRES_PASSWORD=`set +x;shared_get_info.sh POST POSTGRES_PASSWORD;set -x`
        set -x
        initdb -D ${TX_MONITOR_APP_DIR}
        pg_ctl -D ${TX_MONITOR_APP_DIR} -l logfile start
        sed -i "s/trust$/scram-sha-256/" ${TX_MONITOR_APP_DIR}/pg_hba.conf
        #https://docs.gitea.com/installation/datamonitor-prep create using default US UTF8 set in base container 
        psql -c "CREATE DATABASE $TX_POSTGRES_DB  TEMPLATE template0;"
        set +x;psql -q -c "CREATE USER $TX_POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';"; set -x
        psql -c "GRANT ALL PRIVILEGES ON DATABASE $TX_POSTGRES_DB TO $TX_POSTGRES_USER;"
        psql -c "ALTER DATABASE $TX_POSTGRES_DB OWNER TO $TX_POSTGRES_USER"
        #https://www.postgresql.org/docs/16/auth-pg-hba-conf.html
        psql -c "ALTER SYSTEM SET ssl TO 'on';"
        psql -c "ALTER SYSTEM SET ssl_cert_file TO '/home/postgres/cert/${CERT_NAME}.crt';"
        psql -c "ALTER SYSTEM SET ssl_key_file TO '/home/postgres/cert/${CERT_NAME}.key';"
        psql -c "ALTER SYSTEM SET ssl_ca_file TO '${STEPPATH}/certs/root_ca.crt';"
# Probably best ot use password but commenting out below password setup in favour of cert only 
#       echo "hostssl    $TX_POSTGRES_DB             $TX_POSTGRES_USER             all               scram-sha-256    clientcert=verify-full" |  tee -a ${TX_MONITOR_APP_DIR}/pg_hba.conf
        echo "hostssl    $TX_POSTGRES_DB             $TX_POSTGRES_USER             localhost               cert" |  tee -a ${TX_MONITOR_APP_DIR}/pg_hba.conf
	ORIG_IFS=$IFS
	IFS=,
	for subnet in ${TX_ALLOWED_SUBNET}; do
        #echo "hostssl    $TX_POSTGRES_DB             $TX_POSTGRES_USER             ${TX_ALLOWED_SUBNET}               cert" |  tee -a ${TX_MONITOR_APP_DIR}/pg_hba.conf
        	echo "hostssl    $TX_POSTGRES_DB             $TX_POSTGRES_USER             ${subnet}               cert" |  tee -a ${TX_MONITOR_APP_DIR}/pg_hba.conf
	done
	IFS=${ORIG_IFS}
        echo "#host    $TX_POSTGRES_DB             $TX_POSTGRES_USER             all               scram-sha-256" |  tee -a ${TX_MONITOR_APP_DIR}/pg_hba.conf
        echo "#hostssl    $TX_POSTGRES_DB             $TX_POSTGRES_USER             `hostname -I`               scram-sha-256" |  tee -a ${TX_MONITOR_APP_DIR}/pg_hba.conf
        sed -i "s/#listen_addresses = 'localhost'/listen_addresses = 'localhost,${HOST_FQDN}'/" ${TX_MONITOR_APP_DIR}/postgresql.conf

}

renew () {

        loginfo "renew certificates"
        step certificate verify ${CERT_LOCATION}/${CERT_NAME}.crt  --roots ${STEPPATH}/certs/root_ca.crt  --host=$HOST_FQDN
        retVal=$?
        if [ $retVal -eq 0 ];then
                loginfo "renew postgres db certificate"
                step ca renew -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
        else
                logwarn "postgres db certificate expired or other error "
                loginfo "recreate postgres db certificate"
                rm -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
                step ca certificate ${TX_CONTAINER_NAME} ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${TX_POST_CERT_DUR} --san ${TX_CONTAINER_NAME} --san $HOST_FQDN  --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
        fi

}

config_file () {

	loginfo "config_file"

}


startup () {

        loginfo "startup postgres - first stop database to check status"
        pg_ctl -D ${TX_MONITOR_APP_DIR} -l logfile stop
        retVal=$?
        if [[ $retVal -eq 0 ]];then
                echo "down" >${TX_DB_SHARED_LOCATION}/${STATUS_FILE}
        else
                echo "unknown" >${TX_DB_SHARED_LOCATION}/${STATUS_FILE}
                logwarn "unknown postgres status, so remove any postmaster.pid file"
                rm -rf ${TX_MONITOR_APP_DIR}/postmaster.pid
        fi
        loginfo "start database"
        pg_ctl -D ${TX_MONITOR_APP_DIR} -l logfile start
        retVal=$?
        if [[ $retVal -eq 0 ]];then
                echo "up" >${TX_DB_SHARED_LOCATION}/${STATUS_FILE}
        else
                echo "down"  >${TX_DB_SHARED_LOCATION}/${STATUS_FILE}
                logerr "unknown postgres status"
        fi

}

post_startup_init () {

	loginfo "post start initialisation actions"

}

stopapp () {

        loginfo "stopping "
        loginfo "stop database"
        pg_ctl -D ${TX_MONITOR_APP_DIR} -l logfile stop
        retVal=$?
        if [ $retVal -eq 0 ];then
                loginfo "database stopped"
        fi
        echo "down" >${TX_DB_SHARED_LOCATION}/${STATUS_FILE}
        rm -rf ${TX_MONITOR_APP_DIR}/postmaster.pid


}

shutdown_stopapp () {

	stopapp
	exit 0

}


andcheck () {

        loginfo "sleeping and checking certificate expiry"
        while true
        do
                step certificate needs-renewal --expires-in ${TX_POST_EXP_CHECK}  ${CERT_LOCATION}/${CERT_NAME}.crt
                retVal=$?
                if [ $retVal -eq 0 ];then
                        renew
                        loginfo "reload database to refresh certificate"
                        pg_ctl reload -D ${TX_MONITOR_APP_DIR}
                fi
        sleep 10m
        done

}


trap shutdown_stopapp TERM INT


if [ ! -f ${INST_LOCFILE} ];then
        if check_step_ca 4 10; then
                loginfo "setup Postgress"
                initialise_app
                #config_file
                startup
                        #POSTGRES_PASSWORD=`set +x;shared_get_info.sh POST POSTGRES_PASSWORD;set -x`
                        #psql -P pager=off "dbname=$TX_POSTGRES_DB  user=$TX_POSTGRES_USER password=$POSTGRES_PASSWORD" -c "SELECT * FROM pg_catalog.pg_tables;"
                #post_startup_init
                sleep 10
                andcheck
        else
                logerr "Exiting setup as step ca cant be contacted"
        fi


else
        
        if check_step_ca 2 10; then
                loginfo "Renew certificate and startup Postgres"
                renew
                startup
                andcheck
        else
                logerr "Failure to connect to step-ca - cant renew certificates but starting Postgres and certificates may cause issues "
                startup
                andcheck      
        fi

fi


tail -f /dev/null

