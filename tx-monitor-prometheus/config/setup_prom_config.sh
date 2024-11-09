#!/bin/bash

alert_conf_file () {
cat << EOF > ${ALER_CONFIG_FILE}
global:
  # SMTP configuration for email notifications (if needed)
  smtp_smarthost: 'mailserver.example.com:587'
  smtp_from: 'alertmanager@example.com'
  smtp_auth_username: 'alertmanager'
  smtp_auth_password: 'your_password'

route:
  group_by: ['critical','alertname','severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default-receiver'

receivers:
  - name: 'default-receiver'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF
}

prom_conf_file () {
cat << EOF > ${PROM_CONFIG_FILE}
# my global config
global:
  scrape_interval: 30s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 30s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# Alertmanager configuration
alerting:
  alertmanagers:
  - scheme: https
    tls_config:
      ca_file: ${STEPPATH}/certs/root_ca.crt
      cert_file: ${CERT_LOCATION}/${CERT_NAME}.crt
      key_file: ${CERT_LOCATION}/${CERT_NAME}.key
    static_configs:
        - targets:
           - ${HOST_FQDN}:${TX_ALERTMANAGER_PORT}

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
  - "/srv/conf/first_rules.yml"
  # - "/srv/conf/second_rules.yml"

# A scrape configuration containing exactly one endpoint to scrape:
# Here it's Prometheus itself.
scrape_configs:
  - job_name: 'prometheus-job'
    scheme: https
    tls_config:
      ca_file: ${STEPPATH}/certs/root_ca.crt
      cert_file: ${CERT_LOCATION}/${CERT_NAME}.crt
      key_file: ${CERT_LOCATION}/${CERT_NAME}.key
    static_configs:
    - targets: ['${HOST_FQDN}:${TX_PROMETHEUS_PORT}']
#    - targets: ['${CERT_HOST}:${TX_PROMETHEUS_PORT}']
  - job_name: 'node-my-host'
    scheme: https
    tls_config:
      ca_file: ${STEPPATH}/certs/root_ca.crt
      cert_file: ${CERT_LOCATION}/${CERT_NAME}.crt
      key_file: ${CERT_LOCATION}/${CERT_NAME}.key
    static_configs:
    - targets: ['${MY_HOST_FQDN}:${TX_NODE_EXPORTER_PORT}']
  - job_name: 'linux-service'
    scheme: https
    tls_config:
      ca_file: ${STEPPATH}/certs/root_ca.crt
      cert_file: ${CERT_LOCATION}/${CERT_NAME}.crt
      key_file: ${CERT_LOCATION}/${CERT_NAME}.key
    dns_sd_configs:
      - names:
          - '_linsrv._tcp.${LOCAL_DOMAIN_NAME}'
        type: 'SRV'
        refresh_interval: '30s'
  - job_name: 'windows-service'
    scheme: https
    tls_config:
      ca_file: ${STEPPATH}/certs/root_ca.crt
      cert_file: ${CERT_LOCATION}/${CERT_NAME}.crt
      key_file: ${CERT_LOCATION}/${CERT_NAME}.key
    dns_sd_configs:
      - names:
          - '_winsrv._tcp.${LOCAL_DOMAIN_NAME}'
        type: 'SRV'
        refresh_interval: '30s'
EOF
}

webconfig_file () {
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

webconfig_file () {
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

amtoolhttp_file () {
cat << EOF > ${AMTOOL_FILE}
tls_config:
  ca_file: ${STEPPATH}/certs/root_ca.crt
  cert_file: ${CERT_LOCATION}/${CERT_NAME}.crt
  key_file: ${CERT_LOCATION}/${CERT_NAME}.key
EOF

}

first_rules () {
cat << EOF > /srv/conf/first_rules.yml
groups:
  - name: AllInstances
    rules:
    - alert: InstanceDown
      # Condition for alerting
      expr: up == 0
      for: 1m
      # Annotation - additional informational labels to store more information
      annotations:
        title: 'Instance {{ \$labels.instance }} down'
        description: '{{ \$labels.instance }} of job {{ \$labels.job }} has been down for more than 1 minute.'
      # Labels - additional labels to be attached to the alert
      labels:
        severity: 'critical'
  - name: linux_filesystem_alerts
    rules:
    - alert: LinuxFilesystemLowSpace
      expr: (node_filesystem_size_bytes{fstype!~"tmpfs|fuse.lxcfs|vfat"} - node_filesystem_free_bytes{fstype!~"tmpfs|fuse.lxcfs|vfat"}) / node_filesystem_size_bytes{fstype!~"tmpfs|fuse.lxcfs|vfat"} * 100 > 80
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Filesystem low space on {{ \$labels.instance }}"
        description: "Filesystem on {{ \$labels.device }} at {{ \$labels.mountpoint }} has less than 20% free space left. Current usage: {{ \$value }}%."
    - alert: LinuxFilesystemCriticallyLowSpace
      expr: (node_filesystem_size_bytes{fstype!~"tmpfs|fuse.lxcfs|vfat"} - node_filesystem_free_bytes{fstype!~"tmpfs|fuse.lxcfs|vfat"}) / node_filesystem_size_bytes{fstype!~"tmpfs|fuse.lxcfs|vfat"} * 100 > 90
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Filesystem critically low space on {{ \$labels.instance }}"
        description: "Filesystem on {{ \$labels.device }} at {{ \$labels.mountpoint }} has less than 10% free space left. Current usage: {{ \$value }}%."
  - name: windows_disk_alerts
    rules:
    - alert: WinDiskSpaceUsage
      expr: 100.0 - 100 * (windows_logical_disk_free_bytes / windows_logical_disk_size_bytes) > 95
      for: 10m
      labels:
        severity: high
      annotations:
        summary: "Disk Space Usage (instance {{ \$labels.instance }})"
        description: "Disk Space on Drive is used more than 95%\n  VALUE = {{ \$value }}\n  LABELS: {{ \$labels }}"

    # Alerts on disks with over 85% space usage predicted to fill within the next four days
    - alert: WinDiskFilling
      expr: 100 * (windows_logical_disk_free_bytes / windows_logical_disk_size_bytes) < 15 and predict_linear(windows_logical_disk_free_bytes[6h], 4 * 24 * 3600) < 0
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Disk full in four days (instance {{ \$labels.instance }})"
        description: "{{ \$labels.volume }} is expected to fill up within four days. Currently {{ \$value | humanize }}% is available.\n VALUE = {{ \$value }}\n LABELS: {{ \$labels }}"
EOF
}


alert_conf_file
prom_conf_file
webconfig_file
first_rules
amtoolhttp_file


