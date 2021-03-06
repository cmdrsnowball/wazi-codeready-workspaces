#!/bin/bash

# script to generate a manifest of all the rpms installed into the containers

allNVRs=""
MATCH=""
quiet=0
HELP="

How to use this script:
NVR1 NVR2 ...   | list of NVRs to query. If omitted, generate list from crw-2.0-rhel-8-candidate
-h,     --help  | show this help menu
-g \"regex\"      | if provided, grep resulting rpm logs for matching regex

Examples:
$0 codeready-workspaces-stacks-node-container-2.0-12.1552519049 codeready-workspaces-stacks-java-container

$0 stacks-dotnet -g \"/(libssh2|python|python-libs).x86_64\" # check one container for version of two rpms

$0 # to generate overall log for all latest NVRs
"
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-h'|'--help') echo -e "$HELP"; exit 1;;
    '-g')          MATCH="$2";     shift 2;;
    '-q')          quiet=1;        shift 1;;
    *)  allNVRs="${allNVRs} $1"; shift 1;;
  esac
done

cd /tmp
MANIFEST_FILE=/tmp/manifest-rpms.txt
MANIFEST_UNIQ_FILE=/tmp/manifest-rpms_uniq.txt
LOG_FILE=/tmp/manifest-rpms_log.txt
rm -fr ${MANIFEST_FILE} ${LOG_FILE}

function log () {
	if [[ $quiet -eq 0 ]]; then 
		echo "$1" | tee -a ${LOG_FILE}
	fi
}
function mnf () {
	echo "$1" | tee -a ${MANIFEST_FILE}
}
function bth () {
	echo "$1" >> ${MANIFEST_FILE}
	echo "$1" | tee -a ${LOG_FILE}
}

function loadNVRs() {
	pushd /tmp >/dev/null
	curl -sSLO https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/master/product/getLatestImageTags.sh
	chmod +x getLatestImageTags.sh
	/tmp/getLatestImageTags.sh --nvr | tee /tmp/getLatestImageTags.sh.nvrs.txt
	loadNVRs_return="$(cat /tmp/getLatestImageTags.sh.nvrs.txt)"
	popd >/dev/null
}

function loadNVRlog() {
	NVR=$1
	MANIFEST_FILE2=$2
	URL=$(echo $NVR | sed -e "s#\(.\+\(-container\|-rhel8\)\)-\([0-9.]\+\)-\([0-9.]\+\)#http://download.eng.bos.redhat.com/brewroot/packages/\1/\3/\4/data/logs/x86_64-build.log#")
	# log ""
	log "   ${URL}"

	input=/tmp/${NVR}.log
	curl -s $URL -o $input
	collecting=0
	while IFS= read -r line
	do
		# echo "[$collecting] $line"
		if [[ $line == "Installed Packages" ]]; then # start collecting lines
			collecting=1
			continue
		elif [[ $line == "End Of Installed Packages" ]]; then
			# echo "${NVR}    $line" >> ${MANIFEST_FILE}
			if [[ $quiet -eq 0 ]]; then echo ""; else echo "   $NVR" | tee -a ${LOG_FILE}; fi
			break
		fi
		if [[ $collecting -eq 1 ]] && [[ $line ]]; then
			# rh-maven35-maven-lib.noarch                               1:3.5.0-4.3.el7                @rhel-server-rhscl-7-rpms          
			# NVR = codeready-workspaces-stacks-python-container-2.0-8 (NVR notation)
			# want  codeready-workspaces-stacks-python-container:2.0-8 (prod:version notation)
			echo "${NVR/-container-/-container:}/$(echo $line | sed -e "s#\(.\+\)[\ \t]\+\(.\+\)[\ \t]\+\@.\+#\1-\2#g")" >> ${MANIFEST_FILE}
			echo "${NVR/-container-/-container:}/$(echo $line | sed -e "s#\(.\+\)[\ \t]\+\(.\+\)[\ \t]\+\@.\+#\1-\2#g")" >> ${MANIFEST_FILE2}
		fi
	done < "$input"
	rm -f $input
	if [[ $quiet -eq 0 ]]; then mnf ""; else echo "" >> ${MANIFEST_FILE}; fi
}

if [[ ${allNVRs} == "" ]]; then
	log "Compute list of latest crw-2.0-rhel-8-candidate NVRs ... ";
	loadNVRs; allNVRs="${allNVRs} ${loadNVRs_return}"
	log ""
fi
log "NVRs to query for installed rpms:"
for NVR in ${allNVRs}; do
	log "   $NVR"
done

log ""

# allNVRs=codeready-workspaces-stacks-python-container-2.0-6
log "Brew logs:"
for NVR in ${allNVRs}; do
	MANIFEST_FILE2=/tmp/manifest-rpms-${NVR}.txt
	rm -fr ${MANIFEST_FILE2}
	loadNVRlog $NVR ${MANIFEST_FILE2}
done

if [[ $quiet -eq 0 ]]; then
	log "" 
	log "NVR build IDs:" 
	for NVR in ${allNVRs}; do 
		buildID=$(brew buildinfo $NVR | grep BUILD | sed -e "s#BUILD: $NVR \[\(.\+\)\]#\1#")
		log "   $NVR [${buildID}] - https://brewweb.engineering.redhat.com/brew/buildinfo?buildID=${buildID}"
	done
fi

##################################

# get uniq list of RPMs
cat /tmp/manifest-rpms-codeready-workspaces-* | sed -r -e "s#.+:2.1-[0-9]+/# #g" | sort | uniq > ${MANIFEST_UNIQ_FILE}

##################################

echo "" | tee -a ${LOG_FILE}
echo "Overall RPM manifest is in file: ${MANIFEST_FILE}" | tee -a ${LOG_FILE}
echo "Unique RPM manifest is in file: ${MANIFEST_UNIQ_FILE}" | tee -a ${LOG_FILE}
echo "Long RPM log is in file: ${LOG_FILE}" | tee -a ${LOG_FILE}
echo "" | tee -a ${LOG_FILE}
echo "Individual RPM manifests:" | tee -a ${LOG_FILE}
for NVR in ${allNVRs}; do 
	echo "* /tmp/manifest-rpms-${NVR}.txt" | tee -a ${LOG_FILE}
	if [[ ${MATCH} ]]; then
		egrep "${MATCH}" /tmp/manifest-rpms-${NVR}.txt | sed -e "s#${NVR/container-/container:}/#    #" | tee -a ${LOG_FILE}
	fi
done
echo "" | tee -a ${LOG_FILE}

cat /tmp/manifest-rpms-codeready-workspaces-* | sed -r -e "s#.+:2.1-[0-9]+/# #g" | sort | uniq > ${MANIFEST_UNIQ_FILE}

##################################
