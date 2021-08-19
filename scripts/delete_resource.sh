RESOURCE_TYPES="
 APIConnectCluster
 Dashboard
 DataPowerService
 DesignerAuthoring
 EventStreams
 QueueManager
 OperationsDashboard
 AssetRepository
 PlatformNavigator"

 for resource_type in ${RESOURCE_TYPES}; do
     echo "Deleting operands for resource type: $resource_type"
     oc delete ${resource_type} -n $1 --all
 done