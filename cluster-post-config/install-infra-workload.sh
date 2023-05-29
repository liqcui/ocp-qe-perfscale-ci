#!/bin/bash

#set -o nounset
#set -o errexit
#set -o pipefail
source ./common.sh
if test ! -f "${KUBECONFIG}"
then
	echo "No kubeconfig, can not continue."
	exit 0
fi

IF_INSTALL_INFRA_WORKLOAD=${IF_INSTALL_INFRA_WORKLOAD:-true}
if [[ ${IF_INSTALL_INFRA_WORKLOAD} != "true" ]];then
   echo "No need to install infra and workload for this OCP cluster"
   exit 1
fi

# Download jq
if [ ! -d /tmp/bin ];then
  mkdir /tmp/bin
  export PATH=$PATH:/tmp/bin
  curl -sL https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 > /tmp/bin/jq
  chmod ug+x /tmp/bin/jq
fi

#Get Basic Infrastructue Architecture Info
node_arch=$(oc get nodes -ojsonpath='{.items[*].status.nodeInfo.architecture}')
platform_type=$(oc get infrastructure cluster -o=jsonpath={.status.platformStatus.type})
platform_type=$(echo $platform_type | tr -s 'A-Z' 'a-z')
node_arch=$(echo $node_arch | tr -s " " "\n"| sort -u)
all_machinesets=$(oc -n openshift-machine-api get machineset -ojsonpath='{.items[*].metadata.name}{"\n"}')
machineset_list=$(echo $all_machinesets | tr -s ' ' '\n'| sort -u| grep -v -i -E "infra|workload|win"| head -n3)
machineset_count=$(echo $all_machinesets | tr -s ' ' '\n'| sort -u| grep -v -i -E "infra|workload|win"| head -n3 |wc -l)
total_worker_nodes=$(oc get nodes -l node-role.kubernetes.io/worker= -oname|wc -l)

#Currently only support AWS reference to ROSA settings
if [[ $total_worker_nodes -gt 100 ]];then
	scale_type=large
elif [[ $total_worker_nodes -gt 26 && $total_worker_nodes -lt 100 ]];then
	scale_type=middle
elif [[ $total_worker_nodes -gt 1 && $total_worker_nodes -lt 25 ]];then
	scale_type=small
fi

######################################################################################
#             CHANGE BELOW VARIABLE IF YOU WANT TO SET DIFFERENT VALUE               #
######################################################################################
export OPENSHIFT_PROMETHEUS_RETENTION_PERIOD=15d
export OPENSHIFT_PROMETHEUS_STORAGE_SIZE=100Gi
export OPENSHIFT_ALERTMANAGER_STORAGE_SIZE=2Gi

case ${platform_type} in
	aws)
           #ARM64 Architecture:
	   if [[ $node_arch == "arm64" ]];then
	      if [[ ${scale_type} == "large" ]];then
                OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=m6g.12xlarge
                OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=m6g.8xlarge
	      elif [[ ${scale_type} == "middle" ]];then
                OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=m6g.8xlarge
                OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=m6g.2xlarge
	      elif [[ ${scale_type} == "small" ]];then
                OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=m6g.2xlarge
                OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=m6g.xlarge
	      fi
	   else
	      if [[ ${scale_type} == "large" ]];then
              #AMD/Standard Architecture:
                OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=r5.4xlarge
                OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=m5.4xlarge
	      elif [[ ${scale_type} == "middle" ]];then
                OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=r5.2xlarge
                OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=m5.2xlarge
	      elif [[ ${scale_type} == "small" ]];then
                OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=r5.xlarge
                OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=m5.xlarge
	      fi
           fi
           #Both Architectures also need:
           OPENSHIFT_INFRA_NODE_VOLUME_TYPE=gp3
           OPENSHIFT_INFRA_NODE_VOLUME_SIZE=500
           OPENSHIFT_INFRA_NODE_VOLUME_IOPS=3000
           OPENSHIFT_WORKLOAD_NODE_VOLUME_TYPE=gp3
           OPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE=500
           OPENSHIFT_WORKLOAD_NODE_VOLUME_IOPS=3000
           OPENSHIFT_PROMETHEUS_STORAGE_CLASS=gp3-csi
           OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=gp3-csi
             ;;
	gcp)
           OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=n1-standard-64
           OPENSHIFT_INFRA_NODE_VOLUME_TYPE=pd-ssd
	   OPENSHIFT_INFRA_NODE_VOLUME_SIZE=100
           OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=n1-standard-32  
           OPENSHIFT_WORKLOAD_NODE_VOLUME_TYPE=pd-ssd
           OPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE=500
           OPENSHIFT_PROMETHEUS_STORAGE_CLASS=ssd-csi
	   OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=ssd-csi
             ;;
	ibmcloud)
	   OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=bx2d-48x192
	   OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=bx2-32x128
	   OPENSHIFT_PROMETHEUS_STORAGE_CLASS=ibmc-vpc-block-5iops-tier
	   OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=ibmc-vpc-block-5iops-tier
           OPENSHIFT_PROMETHEUS_STORAGE_CLASS=ibmc-vpc-block-5iops-tier
	   OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=ibmc-vpc-block-5iops-tier
             ;;
    	openstack)
           OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=ci.m1.xlarge
	   OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=ci.m1.xlarge
           OPENSHIFT_PROMETHEUS_STORAGE_CLASS=standard-csi
           OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=standard-csi
             ;;
	alibabacloud)
	   OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=ecs.g6.13xlarge
	   OPENSHIFT_INFRA_NODE_VOLUME_SIZE=100
	   OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=ecs.g6.8xlarge
	   OPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE=500
	   OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=alicloud-disk
	   OPENSHIFT_PROMETHEUS_STORAGE_CLASS=alicloud-disk
           OPENSHIFT_PROMETHEUS_STORAGE_CLASS=alicloud-disk
           OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=alicloud-disk
             ;;

	azure)
	   #Azure use VM_SIZE as instance type, to unify variable, define all to INSTANCE_TYPE
           OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=Standard_D48s_v3
           OPENSHIFT_INFRA_NODE_VOLUME_TYPE=Premium_LRS
           OPENSHIFT_INFRA_NODE_VOLUME_SIZE=128
           OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=Standard_D32s_v3
           OPENSHIFT_WORKLOAD_NODE_VOLUME_TYPE=Premium_LRS
           OPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE=500
	   OPENSHIFT_PROMETHEUS_STORAGE_CLASS=managed-csi
	   OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=managed-csi
             ;;
	vsphere)
	   OPENSHIFT_INFRA_NODE_VOLUME_SIZE=120
	   OPENSHIFT_INFRA_NODE_CPU_COUNT=48
	   OPENSHIFT_INFRA_NODE_MEMORY_SIZE=196608
	   OPENSHIFT_INFRA_NODE_CPU_CORE_PER_SOCKET_COUNT=2
	   OPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE=500
	   OPENSHIFT_WORKLOAD_NODE_CPU_COUNT=32
	   OPENSHIFT_WORKLOAD_NODE_MEMORY_SIZE=131072
	   OPENSHIFT_WORKLOAD_NODE_CPU_CORE_PER_SOCKET_COUNT=2
             ;;
        nutanix)
	   #nutanix use VM_SIZE as instance type, to uniform variable, define all to INSTANCE_TYPE
           OPENSHIFT_INFRA_NODE_INSTANCE_VCPU=16
	   OPENSHIFT_INFRA_NODE_INSTANCE_MEMORYSIZE=64Gi
	   OPENSHIFT_WORKLOAD_NODE_INSTANCE_VCPU=16
	   OPENSHIFT_WORKLOAD_NODE_INSTANCE_MEMORYSIZE=64Gi
           OPENSHIFT_PROMETHEUS_STORAGE_CLASS=nutanix-volume
           OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=nutanix-volume
	   ;;
        default)
	  ;;
	    
	 *)
	   echo "Un-supported infrastructure cluster detected."
	   exit 1
esac

OPENSHIFT_PROMETHEUS_RETENTION_PERIOD=15d
OPENSHIFT_PROMETHEUS_STORAGE_SIZE=50Gi
OPENSHIFT_ALERTMANAGER_STORAGE_SIZE=1Gi

#Create infra and workload machineconfigpool
create_machineconfigpool infra
create_machineconfigpool workload

#Set default value to none if no specified value, using cpu and ram of worker nodes to create machineset
#This also used for some property don't exist in a certain cloud provider, but need to pass correct parameter for create_machineset
OPENSHIFT_INFRA_NODE_INSTANCE_TYPE=${OPENSHIFT_INFRA_NODE_INSTANCE_TYPE:-none}
OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE=${OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE:-none}
OPENSHIFT_INFRA_NODE_VOLUME_IOPS=${OPENSHIFT_INFRA_NODE_VOLUME_IOPS:-none}
OPENSHIFT_INFRA_NODE_VOLUME_TYPE=${OPENSHIFT_INFRA_NODE_VOLUME_TYPE:-none}
OPENSHIFT_INFRA_NODE_VOLUME_SIZE=${OPENSHIFT_INFRA_NODE_VOLUME_SIZE:-none}
OPENSHIFT_WORKLOAD_NODE_VOLUME_IOPS=${OPENSHIFT_WORKLOAD_NODE_VOLUME_IOPS:-none}
OPENSHIFT_WORKLOAD_NODE_VOLUME_TYPE=${OPENSHIFT_WORKLOAD_NODE_VOLUME_TYPE:-none}
OPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE=${OPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE:-none}
OPENSHIFT_PROMETHEUS_STORAGE_CLASS=${OPENSHIFT_PROMETHEUS_STORAGE_CLASS:-none}
OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=${OPENSHIFT_ALERTMANAGER_STORAGE_CLASS:-none}
OPENSHIFT_PROMETHEUS_RETENTION_PERIOD=${OPENSHIFT_PROMETHEUS_RETENTION_PERIOD:-none}
OPENSHIFT_PROMETHEUS_STORAGE_SIZE=${OPENSHIFT_PROMETHEUS_STORAGE_SIZE:-none}
OPENSHIFT_ALERTMANAGER_STORAGE_SIZE=${OPENSHIFT_ALERTMANAGER_STORAGE_SIZE:-none}
echo OPENSHIFT_INFRA_NODE_INSTANCE_TYPE is $OPENSHIFT_INFRA_NODE_INSTANCE_TYPE
echo OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE is $OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE

#Usage of create_machineset
#create_machineset REF_MACHINESET_NAME NODE_REPLICAS(1) MACHINESET_TYPE(infra/workload) NODE_INSTANCE_TYPE(r5.4xlarge) VOLUME_TYPE(gp3) VOLUME_SIZE(50) VOLUME_IOPS(3000)
#Scale machineset to 3 replicas when only one machineset was found
if [[ $machineset_count -eq 1 && -n $machineset_list ]];then
    echo 1 machineset_list ---- $machineset_list

       machineset=$machineset_list
       create_machineset -m $machineset -r 3 -t infra -x $OPENSHIFT_INFRA_NODE_INSTANCE_TYPE -u $OPENSHIFT_INFRA_NODE_VOLUME_TYPE -v $OPENSHIFT_INFRA_NODE_VOLUME_SIZE -w $OPENSHIFT_INFRA_NODE_VOLUME_IOPS
       create_machineset -m $machineset -r 1 -t workload -x $OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE -u $OPENSHIFT_WORKLOAD_NODE_VOLUME_TYPE -v $OPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE -w $OPENSHIFT_WORKLOAD_NODE_VOLUME_IOPS

elif [[ $machineset_count -eq 2 ]];then
    echo 2 machineset_list ---- $machineset_list
       #The first AZ machineset will scale 2 infra replicas and 1 workload replicas
       machineset=$(echo $machineset_list | awk '{print $1}')
       create_machineset -m $machineset -r 2 -t infra -x $OPENSHIFT_INFRA_NODE_INSTANCE_TYPE -u $OPENSHIFT_INFRA_NODE_VOLUME_TYPE -v $OPENSHIFT_INFRA_NODE_VOLUME_SIZE -w $OPENSHIFT_INFRA_NODE_VOLUME_IOPS
       create_machineset -m $machineset -r 1 -t workload -x $OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE -u $OPENSHIFT_WORKLOAD_NODE_VOLUME_TYPE -v $OPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE -w $OPENSHIFT_WORKLOAD_NODE_VOLUME_IOPS
       #The Second AZ machineset will scale 1 infra replicas 
       machineset=$(echo $machineset_list | awk '{print $2}')
       create_machineset -m $machineset -r 1 -t infra -x $OPENSHIFT_INFRA_NODE_INSTANCE_TYPE -u $OPENSHIFT_INFRA_NODE_VOLUME_TYPE -v $OPENSHIFT_INFRA_NODE_VOLUME_SIZE -w $OPENSHIFT_INFRA_NODE_VOLUME_IOPS

elif [[ $machineset_count -eq 3 ]];then

    for machineset in $machineset_list
    do
       create_machineset -m $machineset -r 1 -t infra -x $OPENSHIFT_INFRA_NODE_INSTANCE_TYPE -u $OPENSHIFT_INFRA_NODE_VOLUME_TYPE -v $OPENSHIFT_INFRA_NODE_VOLUME_SIZE -w $OPENSHIFT_INFRA_NODE_VOLUME_IOPS
    done
       machineset=$(echo $machineset_list | awk '{print $1}')
       create_machineset -m $machineset -r 1 -t workload -x $OPENSHIFT_WORKLOAD_NODE_INSTANCE_TYPE -u $OPENSHIFT_WORKLOAD_NODE_VOLUME_TYPE -v $OPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE -w $OPENSHIFT_WORKLOAD_NODE_VOLUME_IOPS
else
       echo "No machineset was found or abnormal machineset"
fi

IF_MOVE_INGRESS=${IF_MOVE_INGRESS:-true}
if [[ ${IF_MOVE_INGRESS} == "true" ]];then
  move_routers_ingress
fi

IF_MOVE_REGISTRY=${IF_MOVE_REGISTRY:-true}
if [[ ${IF_MOVE_REGISTRY} == "true" ]];then
   move_registry
fi
IF_MOVE_MONITORING=${IF_MOVE_MONITORING:-true}
if [[ ${IF_MOVE_MONITORING} == "true" ]];then
   move_monitoring
fi
