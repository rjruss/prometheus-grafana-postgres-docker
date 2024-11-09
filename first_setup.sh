#!/bin/bash

#set -x

if [[ ! -f .env ]] ;then
    echo "Missing .env file - modify EXAMPLE.env and copy/move to .env"
    exit 1
fi
#READ IN .env
. .env

if [[ $(id -u) -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
elif ! id "${LOCAL_DOCKER_USER}" &>/dev/null; then
    echo "User ${LOCAL_DOCKER_USER} does not exist, please create and run again as root user"
    exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release 
    case "$ID" in
        rocky|almalinux|rhel)
            echo "rhv"
		dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
		dnf install -y docker-ce docker-ce-cli docker-compose-plugin containerd.io  wget curl jq ca-certificates git openssl
            ;;
        ubuntu)
            echo "ubuntu"
	    # Add Docker's official GPG key:
		apt-get -y update
		apt-get -y install wget curl jq ca-certificates git openssl
		apt-get -y install ca-certificates curl
		install -m 0755 -d /etc/apt/keyrings
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
		chmod a+r /etc/apt/keyrings/docker.asc

		# Add the repository to Apt sources:
		echo \
		  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
		  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
		  tee /etc/apt/sources.list.d/docker.list > /dev/null
		apt-get -y update
		apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch)
            echo "arch"
	    exit 1
            ;;
        *)
            echo "$NAME"
	    exit 1
            ;;
    esac
else
    echo "unknown"
    exit 1
fi

echo "install step"
#STEP
if command -v age >/dev/null 2>&1; then
    echo "age is already installed"
else
	echo "installing age"
	  curl -s -L -o /usr/local/bin/age.tgz https://dl.filippo.io/age/latest?for=linux/amd64 \
		&& tar -xzf  /usr/local/bin/age.tgz --strip-components=1 -C /usr/local/bin \
		&& rm -rf /usr/local/bin/age.tgz
fi

echo "install yq"
#yq
if command -v yq >/dev/null 2>&1; then
    echo "yq is already installed"
else
	echo "installing yq"
	YQ_VER=v4.44.3
	YQ_BIN=yq_linux_amd64
	wget https://github.com/mikefarah/yq/releases/download/${YQ_VER}/${YQ_BIN}.tar.gz -O - | tar xz && mv ${YQ_BIN} /usr/bin/yq
fi

if command -v docker >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && command -v age  >/dev/null 2>&1 && command -v yq  >/dev/null 2>&1; then
    echo "All commands are available"
else
    echo "One or more commands are missing docker, jq, age or yq"
    exit
fi

systemctl enable docker
systemctl start docker

if ! grep "^USER_UID" .env;then
	echo "USER_UID=$(id -u ${LOCAL_DOCKER_USER})" >> .env
	echo "USER_GID=$(id -u ${LOCAL_DOCKER_GROUP})" >> .env
else
	echo "warning found USER_UID and USER_GID so overwriting "
	sed -i "s/USER_UID=.*/USER_UID=$(id -u ${LOCAL_DOCKER_USER})/" .env
	sed -i "s/USER_GID=.*/USER_GID=$(id -u ${LOCAL_DOCKER_GROUP})/" .env
fi

echo "setup group details for user"
groupadd -g $TX_SHARED_ENV_GROUP $TX_SHARED_GROUP_NAME
usermod -aG docker ${LOCAL_DOCKER_USER}
usermod -aG sharedenv ${LOCAL_DOCKER_USER}

PERM_DIR=$(pwd)
echo "change permissions of ${PERM_DIR} to  ${LOCAL_DOCKER_USER} for this project"
chown -R ${LOCAL_DOCKER_USER}:${TX_SHARED_GROUP_NAME} ${PERM_DIR}

#LOCAL_DOCKER_VOLUME_DIR=/docker2
echo "create ${LOCAL_DOCKER_VOLUME_DIR} and change ownership and group to ${LOCAL_DOCKER_USER}:${TX_SHARED_GROUP_NAME}"
mkdir -p ${LOCAL_DOCKER_VOLUME_DIR}
chown -R ${LOCAL_DOCKER_USER}:${TX_SHARED_GROUP_NAME}  ${LOCAL_DOCKER_VOLUME_DIR} 
chmod g+w ${LOCAL_DOCKER_VOLUME_DIR}

echo "create docker volumes specified in robert_compose.yml"
#. ./create_docker_volumes.sh
. ./create_docker_multi_volumes.sh

retVal=$?
if [[ "${retVal}" -eq 0 ]];then
	echo "create encrypted secrets in the AGE related volumes --- remove the .POST.info, .STEP.info and .GRAFANA.info files "
	su - ${LOCAL_DOCKER_USER} -c  "cd ${PERM_DIR};./create_secrets_on_volume.sh POST"
	su - ${LOCAL_DOCKER_USER} -c  "cd ${PERM_DIR};./create_secrets_on_volume.sh GRAFANA"
	su - ${LOCAL_DOCKER_USER} -c  "cd ${PERM_DIR};./create_secrets_on_volume.sh STEP"
else
	echo "error creating volumes - exiting script"
	exit 1
fi
echo "create networks and adjust config files"
. ./create_docker_multi_network.sh

echo "end of setup"

