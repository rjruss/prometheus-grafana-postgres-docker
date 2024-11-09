#!/bin/bash
#https://community.grafana.com/t/cannot-import-community-dashboards-using-the-api/89098
# seems a hack to import dashboard via HTTP API
set -x
# Variables
####               DOES NOT WORK ************
GRAFANA_URL="${1}"
# PASS GRAFANA URL e.g. using container name = "https://grafana-run:5007"
GRAFANA_USER="admin"
GRAFANA_PASS=`shared_get_info.sh GRAFANA GRAFANA_PW`
PROMETHEUS_URL="https://${TX_CONTAINER_NAME}:${TX_PROMETHEUS_PORT}"
CA_CERT_PATH=${STEPPATH}/certs/root_ca.crt
export DS_PROMETHEUS="prometheus"

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


CA_CERT=$(awk '{printf "%s\\n", $0}' $CA_CERT_PATH |sed 's/\\n$//')
#awk '{printf "%s\\n", $0}'  /home/grafuser/stepCA.pem |sed 's/\\n$//'

# datasoruce Payload
PAYLOAD=$(cat <<EOF
{
        "name": "prometheus",
        "type": "prometheus",
        "access": "proxy",
        "url": "$PROMETHEUS_URL",
        "basicAuth": false,
        "jsonData": {
                "tlsAuth": false,
                "tlsAuthWithCACert": true
        },
        "secureJsonData": {
                "tlsCACert": "$CA_CERT"
        }

}
EOF
)
#echo $PAYLOAD

create_data_source () {
# Make the API request to add Prometheus as a data source
curl --cacert ${CA_CERT_PATH} -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -u $GRAFANA_USER:$GRAFANA_PASS \
  -d "$PAYLOAD" \
  $GRAFANA_URL/api/datasources
}



create_serv () {
curl -s --cacert ${CA_CERT_PATH} -X POST ${GRAFANA_URL}/api/serviceaccounts \
  -u $GRAFANA_USER:${GRAFANA_PASS} \
  -H "Content-Type: application/json" \
  -d '{
    "name": "grafanaAPIkey",
    "role": "Admin",
    "isDisabled": false,
    "secondsToLive": 0
  }'|jq -r '.id'

}

get_serv_id () {
#echo 10
curl -s --cacert ${CA_CERT_PATH} -X GET "${GRAFANA_URL}/api/serviceaccounts/search?perpage=1&page=1&query=grafanaAPIkey" -u ${GRAFANA_USER}:${GRAFANA_PASS} -H "Content-Type: application/json" | jq -r '.serviceAccounts[].id'

}


create_token () {
# get key and token
curl -s --cacert ${CA_CERT_PATH} -X POST ${GRAFANA_URL}/api/serviceaccounts/${1}/tokens \
  -u ${GRAFANA_USER}:${GRAFANA_PASS} \
  -H "Content-Type: application/json" \
  -d '{ "name": "grafanatoken" }' | jq -r '[.key,.id]|@csv' |sed 's/"//g'
#Accept: application/json
}

delete_token () {
#Needs ID from create
curl -s --cacert ${CA_CERT_PATH} -X DELETE ${GRAFANA_URL}/api/serviceaccounts/${1}/tokens/${2} \
  -u ${GRAFANA_USER}:${GRAFANA_PASS} \
  -H "Content-Type: application/json" \
  -d '{ "name": "grafanatoken" }'
#Accept: application/json

}

download_dash () {
curl -s -O https://raw.githubusercontent.com/grafana/dashboards/master/dashboards/${1}
#node_exporter
curl -s -O https://grafana.com/api/dashboards/1860/revisions/37/download
#windows_exports
#curl -s -O https://grafana.com/api/dashboards/15794/revisions/2/download
}

import_dash () {

curl  --cacert ${CA_CERT_PATH} -X POST \
-H "Content-Type: application/json" \
-H "Accept: application/json" \
-H "Authorization: Bearer ${1}" \
-d @download \
$GRAFANA_URL/api/dashboards/import

}

create_data_source

S_ID=$(create_serv)

S_ID=$(get_serv_id)

echo "-----CREATE TOKEN--------"
IFS=',' read -r TOKEN TOKEN_ID  < <(create_token ${S_ID})
#echo "$TOKEN          $TOKEN_ID"
echo "-------------------------"


#download_dash "1860-node-exporter-full.json"
#import_dash ${TOKEN}


delete_token ${S_ID} ${TOKEN_ID}


echo

