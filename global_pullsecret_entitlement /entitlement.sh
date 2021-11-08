#! /bin/bash

# Update the global pull secret of a OCP cluster  with IBM container entitlement.
# Author :  Jérôme Tarte, jerome.tarte@fr.ibm.com
# license:  Apache License 2.0

# usage :  ./entitlement.sh <your IBM entitlement key>
# Before the run the script, you should be authenticated on the target OCP cluster.


#get the docker auth info
oc extract secret/pull-secret -n openshift-config --keys=.dockerconfigjson --to=. --confirm

# #update the json with icr.io credentials
oc registry login --registry="cp.icr.io" --auth-basic="cp:$1" --to=.dockerconfigjson

# #update the credential on OCP
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=.dockerconfigjson
