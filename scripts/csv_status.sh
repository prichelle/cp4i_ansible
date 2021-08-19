#!/bin/bash

for i in $(oc get csv -n $1 -o custom-columns=CSV:.metadata.name --no-headers)
do
    echo $i
    phase=$(oc get csv -n $1 $i --no-headers -o custom-columns=PHASE:.status.phase)
    echo $phase

    if [ "$phase" != "Succeeded" ] 
    then
        exit 100
    fi
done
exit 0