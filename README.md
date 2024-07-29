# IBM Cloud Pak for Integration installation Ansible script

This repository contains ansible scripts and associated resources to install IBM Cloud Pak for Integration(CP4I) on an Openshift Container Platform (OCP).
It also provides scripts to configure API Connect and to seed Event Endpoint Management.

The installation script includes the following steps:
* Configure the IBM catalog (the current version use only one catalog source)
* Deploy the required operators (all the operators or a selection of operators). The current script version install the CP4I as a cluster scope.
* Install the cert manager and the IBM Foundational service
* Create the entitlement secret in the target namespace.  
* Create an instance of CP4I Platform Navigator and one or multiple CP4I capabilities instances (ACE dashboard, designer, APIC, MQ queuemanager, EventStreams cluster, EventEndpointManager ). 

The version of the script present in the master branch is aligned with v16.1.

## Prerequisites

* Ansible runtime on the environment where the script will be ran. 

[Ansible installation](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) 

On Mac Ansible can be installed using brew.  

Ansible collection to be installed:  
ansible-galaxy collection install kubernetes.core
ansible-galaxy collection install community.general

* An existing OCP instance where the Cloud Pak will be installed.  
* Storage (RWX and RWO) provider that will be used by CP4I installed on OCP. 
* An active OCP cli session (`oc login`) with an user having `cluster-admin` privileges.
* An entitlement key to download IBM certified containers.

The entitlement key can be found at [IBM Container library](https://myibm.ibm.com/products-services/containerlibrary).

The current version doesn't launch the optional scripts that configure APIC and EEM. 
These scripts can be run afterwards.

The script can be re-run if it has been stopped for any reason.

The script has been tested with CP4I v16.1 on OCP 4.16. 

## Installation

1. Clone this git repository
   ``` 
   git clone git@github.com:prichelle/cp4i_ansible.git
   ``` 

2. Go inside the created directory
   ```
   cd cp4i_ansible
   ```

3. Set the Entitlement key 
```
export ENT_KEY=<yourKey>
```

5. Launch the execution of the ansible script
   ```
ansible-playbook -i inventory install/install-playbook.yaml -e ibm_entitlement_key=$ENT_KEY

   ```
TODO: provides output


### Optional scripts

Three scripts are provided to further configure the instances installation.

- API Connect 
This script configure APIC with a mail server, a provider organization and a user.
1. got to the script folder: ./scripts/apic
2. create a credential file "creds.properties" to hold information about user to be created
File structure:
```
APIC_ORG1_USERNAME=<myUser>
APIC_ORG1_PASSWORD=<myPassword>
APIC_ORG1_USER_EMAIL=<myUserEmail>
```
3. launch the script 
```
./apic.config.sh
```
- APIC integration with EEM
If you have installed both APIC and EEM, a script is provided to configure APIC with EEM. 
1. got to the script folder: ./scripts/apic
3. launch the script 
```
./eem_apic_config.sh
```
TODO: APIC configuration done but integration not tested. Could required to restart EEM pod.

- EEM seed
This script will create EventStreams Topic, EEM Topics and a Kafka Connect
1. got to the script folder: ./scripts/eem
3. launch the script 
```
./eem-seed.sh
```
TODO TOPICS configuration options

## Parameters for the `config.json` file

The default configuration install all CP4I capabilities with the latest version.  
This can be changed and configured by adapting the file `./install/config/config.json`.

TODO provides additional information on how to adapt the file
