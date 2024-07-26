################################################
# Download APIC toolkit
# @param org_name: The name of the organisation.
function download_tools () {
  # APIC_NAMESPACE=$(oc get apiconnectcluster -A -o jsonpath='{..namespace}')
  local apic_instance=$(oc -n "${MY_APIC_PROJECT}" get apiconnectcluster -o=jsonpath='{.items[0].metadata.name}')
  local lf_file2download
  local toolkit_creds_url
  
  case "${PLATFORM}" in
    linux)
      lf_file2download="toolkit-linux.tgz"
      lf_unzip_command="tar -xf"
      ;;
    windows)
      lf_file2download="toolkit-windows.zip"
      lf_unzip_command="unzip";;
    mac)
      lf_file2download="toolkit-mac.zip"
      lf_unzip_command="unzip";;
  esac

  mylog info "checking is already download ./tmp/${lf_file2download}"


  if [ -e "./tmp/${lf_file2download}" ]; then
  	mylog info "$PLATFORM toolkit already downloaded" 1>&2
  else
    mylog info "toolkit ./tmp/$lf_file2download not downloaded"
  	mylog info "Downloading toolkit $PLATFORM" 1>&2
    apic_mgmt_client_downloads_server_pod="$(oc -n ${MY_APIC_PROJECT} get po -l app.kubernetes.io/name=client-downloads-server,app.kubernetes.io/part-of=${apic_instance} -o=jsonpath='{.items[0].metadata.name}')"
    # SB]20240207 using absolute path generate the following error on windows : error: one of src or dest must be a local file specification
    #             use pushd and popd for relative path
    pushd "./tmp"
    oc cp -n "${MY_APIC_PROJECT}" "${apic_mgmt_client_downloads_server_pod}:dist/${lf_file2download}" ${lf_file2download}
    $lf_unzip_command ${lf_file2download} # && mv apic-slim apic
    popd
  fi


  toolkit_creds_url="${PLATFORM_API_URL}api/cloud/settings/toolkit-credentials"
  # always download the credential.json
  # if test ! -e "~/.apiconnect/config-apim";then
  #mylog info "Downloading apic config json file" 1>&2
  #curl -ks "${toolkit_creds_url}" -H "Authorization: Bearer ${access_token}" -H "Accept: application/json" -H "Content-Type: application/json" -o creds.json
  #yes | apic client-creds:set creds.json
  # 	[[ -e creds.json ]] && rm creds.json
  # fi
}

#!/bin/sh

# This script integrate EEM with APIC.

# This script requires the oc command being installed in your environment
# This script requires the jq utility being installed in your environment
# This script requires the apic command being installed in your environment

if [ ! command -v oc &> /dev/null ]; then echo "oc could not be found"; exit 1; fi;
if [ ! command -v jq &> /dev/null ]; then echo "jq could not be found"; exit 1; fi;
if [ ! command -v apic &> /dev/null ]; then echo "apic could not be found"; exit 1; fi;

###################
# INPUT VARIABLES #
###################
starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=${PWD}/

MY_APIC_PROJECT=$(cat ../../config/config.json | jq -r ".instances.apic.namespace")

# Same construction as in cp4i.properties
MY_APIC_INSTANCE_NAME=$(cat ../../config/config.json | jq -r ".instances.apic.cluster.name")

MY_EEM_PROJECT=$(cat ../../config/config.json | jq -r ".instances.eem.namespace")
MY_EEM_INSTANCE_NAME=$(cat ../../config/config.json | jq -r ".instances.eem.manager.name")
MY_EGW_INSTANCE_NAME=$(cat ../../config/config.json | jq -r ".instances.eem.gateway.name")

# load helper functions
. "${scriptdir}"../common/lib.sh
read_config_file "${scriptdir}apic.properties"
read_config_file "${scriptdir}creds.properties"



APIC_MGMT_SERVER=$(oc get route "${MY_APIC_INSTANCE_NAME}-mgmt-platform-api" -n $MY_APIC_PROJECT -o jsonpath="{.spec.host}")
APIC_ADMIN_PWD=$(oc get secret "${MY_APIC_INSTANCE_NAME}-mgmt-admin-pass" -n $MY_APIC_PROJECT -o jsonpath="{.data.password}"| base64 -d)

APIC_JWKS_URL=$(oc get apiconnectcluster $MY_APIC_INSTANCE_NAME -n $MY_APIC_PROJECT -ojsonpath='{.status.endpoints[?(@.name=="jwksUrl")].uri}')
APIC_PLATFORM_API=$(oc get apiconnectcluster $MY_APIC_INSTANCE_NAME -n $MY_APIC_PROJECT -ojsonpath='{.status.endpoints[?(@.name=="platformApi")].uri}' | cut -b 9- | cut -d/ -f1)

mylog info "retrieving platform api cert at $APIC_PLATFORM_API"
echo -n | openssl s_client -connect $APIC_PLATFORM_API:443 -servername $APIC_PLATFORM_API -showcerts | openssl x509 > ./tmp/$MY_APIC_INSTANCE_NAME-platform-api.pem

oc create secret generic ${MY_APIC_INSTANCE_NAME}-cpd --from-file=ca.crt=./tmp/${MY_APIC_INSTANCE_NAME}-platform-api.pem -n ${MY_EEM_PROJECT}

oc get EventEndpointManagement ${MY_EEM_INSTANCE_NAME} -n ${MY_EEM_PROJECT} -o json \
  | jq --arg MY_APIC_INSTANCE_NAME $MY_APIC_INSTANCE_NAME \
       --arg APIC_JWKS_URL $APIC_JWKS_URL \
  '.spec.manager.apic.jwks += {"endpoint": ($APIC_JWKS_URL)} | 
  .spec.manager.apic += {"clientSubjectDN":"CN=ingress-ca"} | 
  .spec.manager.tls += {"trustedCertificates":[{"certificate":"ca.crt","secretName":($MY_APIC_INSTANCE_NAME + "-cpd")}]}' \
  | oc apply -f -

oc get secret ${MY_APIC_INSTANCE_NAME}-ingress-ca -n ${MY_APIC_PROJECT} -o jsonpath="{.data.ca\.crt}" | base64 -D > ./tmp/${MY_APIC_INSTANCE_NAME}-ca.pem
oc get secret ${MY_APIC_INSTANCE_NAME}-ingress-ca -n ${MY_APIC_PROJECT} -o jsonpath="{.data.tls\.crt}" | base64 -D > ./tmp/${MY_APIC_INSTANCE_NAME}-tls-crt.pem
oc get secret ${MY_APIC_INSTANCE_NAME}-ingress-ca -n ${MY_APIC_PROJECT} -o jsonpath="{.data.tls\.key}" | base64 -D > ./tmp/${MY_APIC_INSTANCE_NAME}-tls-key.pem

APIC_MGMT_SERVER=$(oc get route "${MY_APIC_INSTANCE_NAME}-mgmt-platform-api" -n $MY_APIC_PROJECT -o jsonpath="{.spec.host}")
APIC_ADMIN_PWD=$(oc get secret "${MY_APIC_INSTANCE_NAME}-mgmt-admin-pass" -n $MY_APIC_PROJECT -o jsonpath="{.data.password}"| base64 -d)

mylog info "using mgmt url: $APIC_MGMT_SERVER"
download_tools

chmod +x ./tmp/apic
#################
# LOGIN TO APIC #
#################
echo "Login to APIC with CMC Admin User..."


./tmp/apic client-creds:clear
./tmp/apic login --server $APIC_MGMT_SERVER --realm admin/default-idp-1 -u admin -p $APIC_ADMIN_PWD

### Create keystore
cat ./tmp/$MY_APIC_INSTANCE_NAME-tls-crt.pem ./tmp/$MY_APIC_INSTANCE_NAME-tls-key.pem > ./tmp/$MY_APIC_INSTANCE_NAME-tls-combined.pem
APIC_CERT=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' ./tmp/$MY_APIC_INSTANCE_NAME-tls-combined.pem)

#     topic_data=$(cat ./templates/10-eem-eventsource-$topic.json | jq '.clusterId |= '${clusterId}'')
( echo "cat <<EOF" ; cat ./templates/eem-apic-keystore.json ;) | \
    MY_APIC_INSTANCE_NAME=${MY_APIC_INSTANCE_NAME} \
    APIC_CERT=${APIC_CERT} \
    sh > ./tmp/eem-apic-keystore.json

./tmp/apic keystores:create --server $APIC_MGMT_SERVER --org admin --format json ./tmp/eem-apic-keystore.json --output ./tmp

if [ $? -eq 0 ]; then
    echo "The command was successful."
else
   ./tmp/apic keystores:get --server $APIC_MGMT_SERVER --org admin --format json eem-keystore --output ./tmp
fi

### Create Truststore
APIC_CERT=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' ./tmp/$MY_APIC_INSTANCE_NAME-ca.pem)
( echo "cat <<EOF" ; cat ./templates/eem-apic-truststore.json ;) | \
    MY_APIC_INSTANCE_NAME=${MY_APIC_INSTANCE_NAME} \
    APIC_CERT=${APIC_CERT} \
    sh > ./tmp/eem-apic-truststore.json
./tmp/apic truststores:create --server $APIC_MGMT_SERVER --org admin --format json ./tmp/eem-apic-truststore.json --output ./tmp

if [ $? -eq 0 ]; then
    echo "The command was successful."
else
   ./tmp/apic truststores:get --server $APIC_MGMT_SERVER --org admin --format json eem-truststore --output ./tmp
fi

mylog info "getting keystore and trustore url"
### Create TLS-Client-Profile
KEYSTORE_URL=$(apic keystores:get eem-keystore --server $APIC_MGMT_SERVER --org admin | awk '{print$3}')
TRUSTSTORE_URL=$(apic truststores:get eem-truststore --server $APIC_MGMT_SERVER --org admin | awk '{print$3}')

mylog info "keystore url $KEYSTORE_URL"

( echo "cat <<EOF" ; cat ./templates/eem-apic-tls-client-profile.json ;) | \
    KEYSTORE_URL=${KEYSTORE_URL} \
    TRUSTSTORE_URL=${TRUSTSTORE_URL} \
    sh > ./tmp/eem-apic-tls-client-profile.json

./tmp/apic tls-client-profiles:create --server $APIC_MGMT_SERVER --org admin --format json ./tmp/eem-apic-tls-client-profile.json --output ./tmp

### Register the event gateway
EEM_MANAGER_APIC_HOST=$(oc get route $MY_EEM_INSTANCE_NAME-ibm-eem-apic -n $MY_EEM_PROJECT --template='{{ .spec.host }}')
EEM_GATEWAY_RT_HOST=$(oc get route $MY_EGW_INSTANCE_NAME-ibm-egw-rt -n $MY_EEM_PROJECT --template='{{ .spec.host }}')

MY_APIC_INSTANCE_NAME_TLS_CLIENT_PROFILE_URL=$(./tmp/apic tls-client-profiles:list-all --server $APIC_MGMT_SERVER --org admin  | grep eem-tls-client-profile | awk '{print$2}')
mylog info "tls client profile url $MY_APIC_INSTANCE_NAME_TLS_CLIENT_PROFILE_URL"
DEFAULT_TLS_SERVER_PROFILE_URL=$(./tmp/apic tls-server-profiles:list-all --server $APIC_MGMT_SERVER --org admin | grep tls-server-profile-default | awk '{print$2}')
mylog info "tls server profile url $DEFAULT_TLS_SERVER_PROFILE_URL"

./tmp/apic integrations:get event-gateway --subcollection gateway-service --server $APIC_MGMT_SERVER --format json --fields url --output ./tmp
INTEGRATION_URL=$(jq -r '.url' ./tmp/Integration.json)

mylog info "integration url $INTEGRATION_URL"

( echo "cat <<EOF" ; cat ./templates/eem-apic-event-gateway.json ;) | \
    EEM_MANAGER_APIC_HOST=${EEM_MANAGER_APIC_HOST} \
    EEM_GATEWAY_RT_HOST=${EEM_GATEWAY_RT_HOST} \
    APIC_INST_NAME_TLS_CLIENT_PROFILE_URL=${MY_APIC_INSTANCE_NAME_TLS_CLIENT_PROFILE_URL} \
    DEFAULT_TLS_SERVER_PROFILE_URL=${DEFAULT_TLS_SERVER_PROFILE_URL} \
    INTEGRATION_URL=${INTEGRATION_URL} \
    sh > ./tmp/eem-apic-event-gateway.json

mylog info "registring gateway service"
./tmp/apic gateway-services:create --server $APIC_MGMT_SERVER --availability-zone availability-zone-default --org admin --format json ./tmp/eem-apic-event-gateway.json --output ./tmp



#rm -f Integration.json
echo "Event Endpoint Manager has been registered with APIC."