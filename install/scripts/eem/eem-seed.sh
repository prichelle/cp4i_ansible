################################################################################################
# Start of the script main entry
# main

# https://ibm.github.io/event-automation/eem/security/api-tokens/#creating-a-token to get the access token 

starting=$(date);

scriptdir=${PWD}/

. "${scriptdir}"../common/lib.sh
read_config_file "${scriptdir}eem.properties"

IFS=',' read -r -a topics <<< "$TOPICS_LIST"
IFS=',' read -r -a topicOptions <<< "$TOPIC_OPTIONS_LIST"


export es_usr_admin="es-admin"

MY_EEM_PROJECT=$(cat ../../config/config.json | jq -r ".instances.eem.namespace")
MY_EEM_INSTANCE_NAME=$(cat ../../config/config.json | jq -r ".instances.eem.manager.name")
MY_ES_PROJECT=$(cat ../../config/config.json | jq -r ".instances.es.namespace")
MY_ES_INSTANCE_NAME=$(cat ../../config/config.json | jq -r ".instances.es.cluster.name")

if [ $# -ne 1 ]; then
  mylog error "missing argument: access token"
  mylog info "log into eem and define access token: go to your profile and create an access token"
  EP_EEM=$(oc -n ${MY_EEM_PROJECT} get route "${MY_EEM_INSTANCE_NAME}-ibm-eem-manager" -o jsonpath="{.spec.host}")
  mylog info "url to access APIC ADMIN : https://$EP_EEM"
  getCredSecret "$MY_EEM_PROJECT" "$MY_EEM_INSTANCE_NAME-ibm-eem-user-credentials" ".data.user-credentials\.json"
  mylog info "credentials to use $cred_out"
  exit
fi



eem_at=$1

mylog info "running script with EEM instance $MY_EEM_INSTANCE_NAME in NS $MY_EEM_PROJECT and ES instance $MY_ES_INSTANCE_NAME in NS $MY_ES_PROJECT"

starting=$(date);

# end with / on purpose (if var not defined, uses CWD - Current Working Directory)
scriptdir=${PWD}/


# Creation de Topics
SECONDS=0

## --------------

mylog info "STEP 1: getting eem host using: oc get route -n $MY_EEM_PROJECT ${MY_EEM_INSTANCE_NAME}-ibm-eem-admin -ojsonpath='https://{.spec.host}'"
export eem_api_host=$(oc get route -n $MY_EEM_PROJECT ${MY_EEM_INSTANCE_NAME}-ibm-eem-admin -ojsonpath='https://{.spec.host}')
export es_boostrap_svc=${MY_ES_INSTANCE_NAME}-kafka-bootstrap.${MY_ES_PROJECT}.svc

mylog info "es bootstrap used: ${es_boostrap_svc}"
mylog info "eem api used: ${eem_api_host}"

mylog info "STEP 2: getting ES credentials"

export es_certificate=$(oc get secret $MY_ES_INSTANCE_NAME-cluster-ca-cert -o jsonpath='{.data.ca\.crt}' -n $MY_ES_PROJECT| base64 -d | awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}')
export es_user_pwd=$(oc get secret $es_usr_admin -n $MY_ES_PROJECT -ojsonpath='{.data.password}' | base64 -d)


mylog info "pwd for $es_usr_admin : $es_user_pwd "

envsubst < "./templates/eem-es-cluster.json" > ./tmp/gen-eem-es-cluster.json

mylog info "STEP 3: registering cluster "
#@${EEM_GEN_CUSTOMDIR}config/eem-es-cluster.json
 eem_response=$(curl -X POST -sk \
      --dump-header ./tmp/eem-api-header \
     -H 'Accept: application/json' \
     -H 'Content-Type: application/json' \
     -H "Authorization: Bearer ${eem_at}" \
     --data "@./tmp/gen-eem-es-cluster.json" \
     --output ./tmp/eem-resp-new-cluster.json \
     --write-out '%{response_code}' \
     $eem_api_host/eem/clusters)

mylog info "response curl: ${eem_response}"

if [ $eem_response -eq 200 ]; then
  clusterId=$(jq .id ./tmp/eem-resp-new-cluster.json)
  mylog info "cluster successfully registered. clusterId: $clusterId"
fi 

if [ $eem_response -eq 409 ]; then
   eem_response=$(curl -sk \
     -H 'Accept: application/json' \
     -H 'Content-Type: application/json' \
     -H "Authorization: Bearer ${eem_at}" \
     --output ./tmp/eem-resp-kafka-clusters.json \
     --write-out '%{response_code}' \
     $eem_api_host/eem/clusters)
    clusterId=$(jq '.[] | select(.["name"] | contains ("'$MY_ES_INSTANCE_NAME'")) | .id' ./tmp/eem-resp-kafka-clusters.json)
  mylog info "Cluster already registered. clusterId: $clusterId"
  mylog info "response curl: ${eem_response}"
fi

if [ $eem_response -ne 200 ]; then
  mylog error "cluster registration failed"
  exit 1
fi 

mylog info "STEP 4: creating topics"

# topics=("CUSTOMERS.NEW" "ORDERS.NEW") # "CANCELLATIONS"" "DOOR.BADGEIN" "ORDERS.NEW")

for topic in "${topics[@]}"
do
    mylog info "processing topic $topic"

    #cat ./templates/10-eem-eventsource-$topic.json | sed "s|CLUSTERID|$clusterId|" > \
    #    ./tmp/eem-request-new-topic.json

    topic_data=$(cat ./templates/10-eem-eventsource-$topic.json | jq '.clusterId |= '${clusterId}'')
    
    #mylog debug "topic  $topic : ${topic_data}"

    # "@./tmp/eem-request-new-topic.json" \

    eem_response=$(curl -X POST -s -k \
          --dump-header ./tmp/eem-api-header \
          -H 'Accept: application/json' \
          -H 'Content-Type: application/json' \
          -H "Authorization: Bearer ${eem_at}" \
          --data "${topic_data}" \
          --output ./tmp/eem-response-data.json \
          --write-out '%{response_code}' \
          $eem_api_host/eem/eventsources)

     if [ $eem_response -eq 200 ]; then
       mv ./tmp/eem-response-data.json ./tmp/eem-response-data-$topic.json
       mylog info "topic $topic added in EEM"
      elif [ $eem_response -eq 409 ]; then
       mylog info "topic $topic already configured in EEM"
      else
        mylog error "not able to create topic"
        mylog info "response: $eem_response"
        exit 
      fi 
     #eventSourceId=$(jq .id ${EEM_GEN_CUSTOMDIR}script/eem-response-data-$topic.json)
done

mylog info "STEP 5: creating options"

#publication of the topic to the event gateway
# topicOptions=("CUSTOMERS.NEW" "ORDERS.NEW") # "ORDERS.NEW" "DOOR.BADGEIN" )

for topicoption in "${topicOptions[@]}"
do
    eventSourceId=$(jq .id ./tmp/eem-response-data-$topicoption.json)
    #mylog info "gw name ${MY_EGW_INSTANCE_NAME}"
    option_data=$(cat ./templates/10-eem-option-$topicoption.json | jq '.eventSourceId |= '${eventSourceId}'' | jq '.gatewayGroups[] |= "'${MY_EGW_INSTANCE_NAME}'"')
    
    # mylog debug "topic option $topicoption : ${option_data}"
    
    eem_response=$(curl -X POST -s -k \
          -H 'Accept: application/json' \
          -H 'Content-Type: application/json' \
          -H "Authorization: Bearer $eem_at" \
          --data "${option_data}" \
          --output ./tmp/eem-rsp-option.json \
          --write-out '%{response_code}' \
          $eem_api_host/eem/options)

    if [ $eem_response -eq 200 ]; then
       mv ./tmp/eem-rsp-option.json ./tmp/eem-rsp-option-$topicoption.json
       mylog info "option for topic $topicoption configured in EEM"
      fi
    if [ $eem_response -eq 409 ]; then
       mylog info "option for topic $topicoption already configured in EEM"
    fi  
done




mylog info "END ## EEM configured."

## --------------

duration=$SECONDS
mylog info "Creation of the Kafka Topics took $duration seconds to execute." 1>&2

ending=$(date);
# echo "------------------------------------"
mylog info "Start: $starting - end: $ending" 1>&2
mylog info "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."  1>&2


