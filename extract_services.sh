#!/bin/bash

if ! command -v yq &> /dev/null ;then
    echo "yq could not be found"
    exit 1
fi


while read i
do
	#Service Extract
	FN="./compose-templates/$i-extracted-compose.yml"
	>${FN}
	echo "services:" |tee -a ${FN}
	echo "  $i:" |tee -a ${FN}
	yq e ".services.${i}" robert_compose.yml | sed "s/^/    /" |tee -a ${FN}

	#VOLUME Extract
	CHK=$(yq e '.volumes // null' robert_compose.yml)
	if [[ "${CHK}" != "null" ]];then
		echo "volumes:"  >>${FN}
		yq e ".services.$i.volumes | .[] | split(\":\")[0]" ${FN}  | while read x;do
			#echo $x
			RN=$(yq e ".volumes.$x" robert_compose.yml)
			if [[ "${RN}" != "null" ]];then
				echo "  $x:" >>${FN}
				echo "    ${RN}" >>${FN}
			fi

		done
	fi

	#Network Extract
        N_CHK=$(yq e '.networks // null' robert_compose.yml)
        #echo $N_CHK
                if [[ "${N_CHK}" != "null" ]];then
                echo "networks:" >>${FN}
                yq e ".services.$i.networks[]" ${FN} |while read nx ;do
                        #echo $nx
                        N_RN=$(yq e ".networks.$nx" robert_compose.yml)
                        if [[ "${N_RN}" != "null" ]];then
                                echo "  $nx:" >>${FN}
                                echo "    ${N_RN}" >>${FN}
                        fi

                done
        fi

	let C++
	CA+=($i)

done < <(yq '.services | keys' robert_compose.yml |sed "s/- //" )

#DOCKER SPLIT - ARG commands will be in split-docker00 and BASE image in split-docker01 and combine with target image
csplit -f split-docker -s -k Dockerfile '/FROM/' {*}

echo ${CA[*]}
rm -f ./compose-templates/*split-docker*
for C in "${CA[@]}"; do 
	echo $C
	D_IMAGE=$(yq e ".services.$C.build.target" robert_compose.yml)
	C_FILENAME=$(grep -l $D_IMAGE split-docker*)
	NEW_DOCKERILE="$C-$C_FILENAME"
	cat $C_FILENAME >> ./compose-templates/${NEW_DOCKERILE}
	echo ${C}
yq -i ".services.$C.build.dockerfile = \"${NEW_DOCKERILE}\"" ./compose-templates/${C}-extracted-compose.yml

done
cat split-docker00 split-docker01  >> ./compose-templates/tx-monitor-dockerfile
rm -f split-docker*
sed -i "s/monitor-img/monitor-img:latest/" ./compose-templates/*docker*
cp .env compose-templates/.
echo "Files in ./compose-templates/."
ls -la compose-templates/.
