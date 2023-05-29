#!/bin/bash
function print_node_machine_info() {

    label=$1
    echo "##########################################Machineset and Node Status##############################"
    oc get machinesets -A
    echo "--------------------------------------------------------------------------------------------------"
    echo
    oc get machines -A
    echo "--------------------------------------------------------------------------------------------------"
    echo
    oc get nodes
    echo "--------------------------------------------------------------------------------------------------"
    echo
    echo "--------------------------------Abnormal Machineset and Node Info---------------------------------"
    for node in $(oc get nodes --no-headers -l node-role.kubernetes.io/$label= | egrep -e "NotReady|SchedulingDisabled" | awk '{print $1}'); do
        oc describe node $node
    done

    for machine in $(oc get machines -n openshift-machine-api --no-headers -l machine.openshift.io/cluster-api-machine-type=$label| grep -v "Running" | awk '{print $1}'); do
        oc describe machine $machine -n openshift-machine-api
    done
}

function set_storage_class() {

    storage_class_found=false
    default_storage_class=""
    # need to verify passed storage class exists 
    for s_class in $(oc get storageclass -A --no-headers | awk '{print $1}'); do
        if [ "$s_class"X != ${OPENSHIFT_PROMETHEUS_STORAGE_CLASS}X ]; then
            s_class_annotations=$(oc get storageclass $s_class -o jsonpath='{.metadata.annotations}')
            default_status=$(echo $s_class_annotations | jq '."storageclass.kubernetes.io/is-default-class"')
            if [ "$default_status" = '"true"' ]; then
                default_storage_class=$s_class
            fi
        else
            storage_class_found=true
        fi
    done
    if [[ $storage_class_found == false ]]; then
        echo "setting new storage classes to $default_storage_class"
        export OPENSHIFT_PROMETHEUS_STORAGE_CLASS=$default_storage_class
        export OPENSHIFT_ALERTMANAGER_STORAGE_CLASS=$default_storage_class
    fi
}

function wait_for_prometheus_status() {
    token=$(oc create token -n openshift-monitoring prometheus-k8s --duration=6h)

    URL=https://$(oc get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
    sleep 30
    max_reties=10
    retry_times=1
    prom_status="not_started"
    echo prom_status is $prom_status
    while [[ "$prom_status" != "success" ]]; do
        prom_status=$(curl -s -g -k -X GET -H "Authorization: Bearer $token" -H 'Accept: application/json' -H 'Content-Type: application/json' "$URL/api/v1/query?query=up" | jq -r '.status')
        echo -e "Prometheus status not ready yet, retrying $retry_times in 5s..."
        sleep 5
        if [[ $retry_times -gt $max_reties ]];then
	      "Out of max retry times, the prometheus still not ready, please check "
	      exit 1
        fi
        retry_times=$(( $retry_times + 1 ))
    done
    if [[ "$prom_status" == "success" ]];then
       echo "######################################################################################"
       echo "#                          The prometheus is ready now!                              #"
       echo "######################################################################################"
    fi
}

function get_ref_machineset_info(){
  machineset_name=$1
  platform_type=$(oc get infrastructure cluster -o=jsonpath={.status.platformStatus.type})
  platform_type=$(echo $platform_type | tr -s 'A-Z' 'a-z')

  if [[ -z ${machineset_name} ]];then
       echo "No machineset was specified, please check"
       exit 1
  else

       echo "Choose $machineset_name as an reference machienset"
  fi
  instance_type=""
  volumeSize=""
  volumeType=""
  volumeIPOS=""
  case ${platform_type} in
       aws)
          instance_type=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.instanceType})
          volumeType=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.blockDevices[*].ebs.volumeType})
          volumeSize=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.blockDevices[*].ebs.volumeSize})
          volumeIPOS=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.blockDevices[*].ebs.iops})
          ;;
       azure)
          instance_type=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.vmSize})
          volumeSize=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.osDisk.diskSizeGB})
          volumeType=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.osDisk.managedDisk.storageAccountType})
          ;;
        gcp)
          instance_type=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.machineType})
          volumeSize=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.disks[*].sizeGb})
          volumeType=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.disks[*].type})
          ;;
        ibmcloud)
          instance_type=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.profile})
          ;;
        alibabacloud)
          instance_type=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.instanceType})
          volumeType=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.systemDisk.category})
          volumeSize=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.systemDisk.size})
          ;;
        openstack)
	  instance_type=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.flavor})
          ;;
        nutanix)
          instance_type=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.vcpuSockets})
          cpusPerSocket=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.vcpusPerSocket})
          memorySize=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.memorySize})
          volumeSize=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.systemDiskSize})
          ;;
        vsphere)
          instance_type=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.numCPUs})
          cpusPerSocket=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.numCoresPerSocket})
          memorySize=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.memoryMiB})
          volumeSize=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.diskGiB})
          volumeType=$(oc -n openshift-machine-api get machineset $machineset_name -ojsonpath={.spec.template.spec.providerSpec.value.kind})
          ;;
        *)
          echo "Non supported platform detected ..."
          exit 1
  esac
  echo -e "\nThe default setting of reference machineset $machineset_name is"
  echo "###########################################################################################"
  if [[ ! -z $instance_type ]];then
      echo instance_type is $instance_type
      export instance_type
  fi

  if [[ ! -z $cpusPerSocket ]];then
      echo PerSocket is $cpusPerSocket
      export cpusPerSocket
  fi

  if [[ ! -z $memorySize ]];then
      echo memorySize is $memorySize
      export memorySize
  fi

  if [[ ! -z $volumeSize ]];then
      echo volumeSize is $volumeSize
      export volumeSize
  fi
  if [[ ! -z $volumeType ]];then
      echo volumeType is $volumeType
      export volumeType
  fi
  if [[ ! -z $volumeIPOS ]];then 
     echo volumeIPOS is $volumeIPOS
     export volumeIPOS
  fi
  echo -e "###########################################################################################\n"
}

function create_machineset() {
    # Get machineset name to generate a generic template

    #REF_MACHINESET_NAME -- Use the specified worker machineset as reference machineset template

    #NODE_REPLICAS -- specify the machineset replicas number

    #MACHINESET_TYPE -- infra or workload machineset

    #NODE_INSTANCE_TYPE -- m5.12xlarge or Standard_D48s_v3 ...

    #VOLUME_TYPE -- gp3. different cloud provider with different name 

    #VOLUME_SIZE -- 100 volume size

    #VOLUME_IOPS -- 3000 volume IPOS
    OPTIND=1
    while getopts m:r:t:x:u:v:w: FLAG
    do
       case "${FLAG}" in
        m) REF_MACHINESET_NAME=${OPTARG}
	   if [[ ${OPTARG} == "none" ]];then
		REF_MACHINESET_NAME=""
           fi
		;;
        r) NODE_REPLICAS=${OPTARG}
	   if [[ ${OPTARG} == "none" ]];then
		NODE_REPLICAS=""
           fi
		;;
        t) MACHINESET_TYPE=${OPTARG}
	   if [[ ${OPTARG} == "none" ]];then
		MACHINESET_TYPE=""
           fi
		;;
        x) NODE_INSTANCE_TYPE=${OPTARG}
    echo ***********************************************
    echo NODE_INSTANCE_TYPE is $NODE_INSTANCE_TYPE 
    echo ***********************************************
	   if [[ ${OPTARG} == "none" ]];then
		NODE_INSTANCE_TYPE=""
           fi
		;;
        u) VOLUME_TYPE=${OPTARG}
	   if [[ ${OPTARG} == "none" ]];then
		VOLUME_TYPE=""
           fi
		;;
        v) VOLUME_SIZE=${OPTARG}
	   if [[ ${OPTARG} == "none" ]];then
		VOLUME_SIZE=""
           fi
		;;
        w) VOLUME_IOPS=${OPTARG}
	   if [[ ${OPTARG} == "none" ]];then
		VOLUME_IOPS=""
           fi
		;;
	*) echo "Invalid parameter, unsupported option ${FLAG}"
           exit 1;;
       esac
    done
    #Optional

    #Get current platform that OCP deploy, aws,gcp,ibmcloud,alicloud etc.
    platform_type=$(oc get infrastructure cluster -o=jsonpath={.status.platformStatus.type})
    platform_type=$(echo $platform_type | tr -s 'A-Z' 'a-z')
    echo platform_type is $platform_type

    #Set default value for key VARIABLE
    #Use the first machineset name by default if no REF_MACHINESET_NAME specified
    ref_machineset_name=$(oc -n openshift-machine-api get -o 'jsonpath={range .items[*]}{.metadata.name}{"\n"}{end}' machinesets | grep worker | head -n1)
    REF_MACHINESET_NAME=${REF_MACHINESET_NAME:-$ref_machineset_name}

    get_ref_machineset_info $REF_MACHINESET_NAME

    #Set default value for variable
    NODE_REPLICAS=${NODE_REPLICAS:-1}
    NODE_INSTANCE_TYPE=${NODE_INSTANCE_TYPE:-$instance_type}
    MACHINESET_TYPE=${MACHINESET_TYPE:-"infra"}
    VOLUME_TYPE=${VOLUME_TYPE:-$volumeType}
    VOLUME_SIZE=${VOLUME_SIZE:-$volumeSize}
    VOLUME_IOPS=${VOLUME_IOPS:-$volumeIPOS}
    echo ***********************************************
    echo NODE_INSTANCE_TYPE is $NODE_INSTANCE_TYPE 
    echo ***********************************************
    # Replace machine name worker to infra
    machineset_name="${REF_MACHINESET_NAME/worker/${MACHINESET_TYPE}}"

    #export ref_machineset_name machineset_name

    # Get a templated json from worker machineset, change machine type and machine name
    # and pass it to oc to create a new machine set

    case ${platform_type} in
        aws)
            oc get machineset ${REF_MACHINESET_NAME} -n openshift-machine-api -o json |
              jq --arg node_instance_type "${NODE_INSTANCE_TYPE}" \
                 --arg machineset_name "${machineset_name}" \
                 --arg volumeType "${VOLUME_TYPE}" \
                 --arg volumeSize "${VOLUME_SIZE}" \
                 --arg volumeIPOS "${VOLUME_IOPS}" \
                 --arg machinesetType "${MACHINESET_TYPE}" \
                 '.metadata.name = $machineset_name |
                  .spec.selector.matchLabels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
                  .spec.template.spec.providerSpec.value.instanceType = $node_instance_type |
                  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
                  .spec.template.spec.providerSpec.value.blockDevices[0].ebs.volumeType = $volumeType |
		  .spec.template.spec.providerSpec.value.blockDevices[0].ebs.volumeSize = ($volumeSize|tonumber) |
		  .spec.template.spec.providerSpec.value.blockDevices[0].ebs.iops = ($volumeIPOS|tonumber) |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
	          .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
		  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
                  del(.status) |
                  del(.metadata.selfLink) |
                  del(.metadata.uid)
                  '>/tmp/machineset.json
            ;;
        azure)
            oc get machineset ${REF_MACHINESET_NAME} -n openshift-machine-api -o json |
              jq --arg node_instance_type "${NODE_INSTANCE_TYPE}" \
                 --arg machineset_name "${machineset_name}" \
                 --arg volumeType "${VOLUME_TYPE}" \
                 --arg volumeSize "${VOLUME_SIZE}" \
                 --arg machinesetType "${MACHINESET_TYPE}" \
                 '.metadata.name = $machineset_name |
                  .spec.selector.matchLabels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
                  .spec.template.spec.providerSpec.value.instanceType = $node_instance_type |
                  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
                  .spec.template.spec.providerSpec.value.osDisk.managedDisk.storageAccountType = $volumeType |
		  .spec.template.spec.providerSpec.value.osDisk.diskSizeGB = ($volumeSize|tonumber) |
	          .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
		  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
                  del(.status) |
                  del(.metadata.selfLink) |
                  del(.metadata.uid)
                  '>/tmp/machineset.json
            ;;
        gcp)
            oc get machineset ${REF_MACHINESET_NAME} -n openshift-machine-api -o json |
              jq --arg node_instance_type "${NODE_INSTANCE_TYPE}" \
                 --arg machineset_name "${machineset_name}" \
                 --arg volumeType "${VOLUME_TYPE}" \
                 --arg volumeSize "${VOLUME_SIZE}" \
                 --arg machinesetType "${MACHINESET_TYPE}" \
                 '.metadata.name = $machineset_name |
                  .spec.selector.matchLabels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
                  .spec.template.spec.providerSpec.value.instanceType = $node_instance_type |
                  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
                  .spec.template.spec.providerSpec.value.disks[0].type = $volumeType |
		  .spec.template.spec.providerSpec.value.disks[0].sizeGb = ($volumeSize|tonumber) |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
	          .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
		  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
                  del(.status) |
                  del(.metadata.selfLink) |
                  del(.metadata.uid)
                  '>/tmp/machineset.json
            ;;
        ibmcloud)
            oc get machineset ${REF_MACHINESET_NAME} -n openshift-machine-api -o json |
              jq --arg node_instance_type "${NODE_INSTANCE_TYPE}" \
                 --arg machineset_name "${machineset_name}" \
                 --arg machinesetType "${MACHINESET_TYPE}" \
                 '.metadata.name = $machineset_name |
                  .spec.selector.matchLabels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
                  .spec.template.spec.providerSpec.value.profile = $node_instance_type |
                  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
	          .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
		  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
                  del(.status) |
                  del(.metadata.selfLink) |
                  del(.metadata.uid)
                  '>/tmp/machineset.json
            ;;
        alibabacloud)
            oc get machineset ${REF_MACHINESET_NAME} -n openshift-machine-api -o json |
              jq --arg node_instance_type "${NODE_INSTANCE_TYPE}" \
                 --arg machineset_name "${machineset_name}" \
                 --arg volumeType "${VOLUME_TYPE}" \
                 --arg volumeSize "${VOLUME_SIZE}" \
                 --arg machinesetType "${MACHINESET_TYPE}" \
                 '.metadata.name = $machineset_name |
                  .spec.selector.matchLabels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
                  .spec.template.spec.providerSpec.value.instanceType = $node_instance_type |
                  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
                  .spec.template.spec.providerSpec.value.systemDisk.category = $volumeType |
		  .spec.template.spec.providerSpec.value.systemDisk.size = ($volumeSize|tonumber) |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
	          .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
		  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
                  del(.status) |
                  del(.metadata.selfLink) |
                  del(.metadata.uid)
                  '>/tmp/machineset.json
               ;;
        vsphere)
		if [[ ${MACHINESET_TYPE} == "infra" ]];then
                   NODE_CPU_COUNT=${OPENSHIFT_INFRA_NODE_CPU_COUNT:-$instance_type}
                   NODE_CPU_CORE_PER_SOCKET_COUNT=${OPENSHIFT_INFRA_NODE_CPU_CORE_PER_SOCKET_COUNT:-$cpusPerSocket}
                   NODE_MEMORY_SIZE=${OPENSHIFT_INFRA_NODE_MEMORY_SIZE:-$memorySize}
		elif [[ ${MACHINESET_TYPE} == "workload"  ]];then
                   NODE_CPU_COUNT=${OPENSHIFT_WORKLOAD_NODE_CPU_COUNT:-$instance_type}
                   NODE_CPU_CORE_PER_SOCKET_COUNT=${OPENSHIFT_WORKLOAD_NODE_CPU_CORE_PER_SOCKET_COUNT:-$cpusPerSocket}
                   NODE_MEMORY_SIZE=${OPENSHIFT_WORKLOAD_NODE_MEMORY_SIZE:-$memorySize}
		else
                   echo -e "Please specify correct ENV variable for vsphere $vsphere:\nOPENSHIFT_INFRA_NODE_VOLUME_SIZE\nOPENSHIFT_INFRA_NODE_CPU_COUNT\OPENSHIFT_INFRA_NODE_MEMORY_SIZE\nOPENSHIFT_INFRA_NODE_CPU_CORE_PER_SOCKET_COUNT\nOPENSHIFT_WORKLOAD_NODE_VOLUME_SIZE\nOPENSHIFT_WORKLOAD_NODE_CPU_COUNT\nOPENSHIFT_WORKLOAD_NODE_MEMORY_SIZE\nOPENSHIFT_WORKLOAD_NODE_CPU_CORE_PER_SOCKET_COUNT\n"
		fi
            oc get machineset ${REF_MACHINESET_NAME} -n openshift-machine-api -o json |
              jq --arg node_instance_type "${NODE_CPU_COUNT}" \
                 --arg numCoresPerSocket "${NODE_CPU_CORE_PER_SOCKET_COUNT}" \
                 --arg ramSize "${NODE_MEMORY_SIZE}" \
                 --arg machineset_name "${machineset_name}" \
                 --arg volumeSize "${VOLUME_SIZE}" \
                 --arg machinesetType "${MACHINESET_TYPE}" \
                 '.metadata.name = $machineset_name |
                  .spec.selector.matchLabels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
		  .spec.template.spec.providerSpec.value.numCPUs = ($node_instance_type|tonumber) |
		  .spec.template.spec.providerSpec.value.numCoresPerSocket = ($numCoresPerSocket|tonumber) |
		  .spec.template.spec.providerSpec.value.memoryMiB = ($ramSize|tonumber) |
                  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
		  .spec.template.spec.providerSpec.value.diskGiB = ($volumeSize|tonumber) |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
	          .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
		  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
                  del(.status) |
                  del(.metadata.selfLink) |
                  del(.metadata.uid)
                  '>/tmp/machineset.json
		;;
        openstack)
            oc get machineset ${REF_MACHINESET_NAME} -n openshift-machine-api -o json |
              jq --arg node_instance_type "${NODE_INSTANCE_TYPE}" \
                 --arg machineset_name "${machineset_name}" \
                 --arg machinesetType "${MACHINESET_TYPE}" \
                 '.metadata.name = $machineset_name |
                  .spec.selector.matchLabels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
		  .spec.template.spec.providerSpec.value.flavor = $node_instance_type |
                  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
	          .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
		  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
                  del(.status) |
                  del(.metadata.selfLink) |
                  del(.metadata.uid)
                  '>/tmp/machineset.json
            ;;
        nutanix)
	    if [[ ${MACHINESET_TYPE} == "infra" ]];then
              INSTANCE_VCPU=${OPENSHIFT_INFRA_NODE_INSTANCE_VCPU:-$instance_type}
              INSTANCE_MEMORYSIZE=${OPENSHIFT_INFRA_NODE_INSTANCE_MEMORYSIZE:-$memorySize}
            elif [[ ${MACHINESET_TYPE} == "workload" ]];then
              INSTANCE_VCPU=${OPENSHIFT_WORKLOAD_NODE_INSTANCE_VCPU:-$instance_type}
              INSTANCE_MEMORYSIZE=${OPENSHIFT_WORKLOAD_NODE_INSTANCE_MEMORYSIZE:-$memorySize}  
            else
	      echo "Please specify correct VARIABLE for nutanix:\n OPENSHIFT_INFRA_NODE_INSTANCE_VCPU\nOPENSHIFT_INFRA_NODE_INSTANCE_MEMORYSIZE\nOPENSHIFT_WORKLOAD_NODE_INSTANCE_VCPU\nOPENSHIFT_WORKLOAD_NODE_INSTANCE_MEMORYSIZE"
	    exit 1
            fi
            oc get machineset ${REF_MACHINESET_NAME} -n openshift-machine-api -o json |
              jq --arg node_instance_type "${INSTANCE_VCPU}" \
                 --arg cpusPerSocket "${cpusPerSocket}" \
                 --arg memorySize "${INSTANCE_MEMORYSIZE}" \
                 --arg machineset_name "${machineset_name}" \
                 --arg machinesetType "${MACHINESET_TYPE}" \
                 '.metadata.name = $machineset_name |
                  .spec.selector.matchLabels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
		  .spec.template.spec.providerSpec.value.vcpuSockets = ($node_instance_type|tonumber) |
		  .spec.template.spec.providerSpec.value.vcpusPerSocket = ($cpusPerSocket|tonumber) |
		  .spec.template.spec.providerSpec.value.memorySize = $memorySize |
                  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machineset" = $machineset_name |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
	          .metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
	          .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-role" = $machinesetType |
		  .spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-type" = $machinesetType |
                  del(.status) |
                  del(.metadata.selfLink) |
                  del(.metadata.uid)
                  '>/tmp/machineset.json
		;;
         *)
		 echo "Un-supported platform $platform_type deletected"
		 exit 1
		 ;;
    esac

    echo
    echo "Information that will be used for deploy $MACHINESET_TYPE nodes" 
    echo "###########################################################################################"
    echo -e "Reference Machineset Name: $REF_MACHINESET_NAME \nNODE_REPLICAS: $NODE_REPLICAS\nMACHINESET_TYPE: $MACHINESET_TYPE\nNODE_INSTANCE_TYPE: $NODE_INSTANCE_TYPE\nINSTANCE_VCPU: $INSTANCE_VCPU\nNODE_CPU_COUNT: $NODE_CPU_COUNT\nNODE_CPU_CORE_PER_SOCKET_COUNT: $NODE_CPU_CORE_PER_SOCKET_COUNT\nINSTANCE_MEMORYSIZE: $INSTANCE_MEMORYSIZE\ncpusPerSocket: $cpusPerSocket\nINSTANCE_MEMORYSIZE: $INSTANCE_MEMORYSIZE\nNODE_MEMORY_SIZE: $NODE_MEMORY_SIZE\nVOLUME_TYPE: $VOLUME_TYPE\nVOLUME_SIZE: $VOLUME_SIZE\nVOLUME_IOPS: $VOLUME_IOPS"
    echo "It's normal if some ENV is empty, vsphere and nutanix use INSTANCE_VCPU/nNODE_CPU_COUNT instead of NODE_INSTANCE_TYPE"
    echo "###########################################################################################"
    if [[ $MACHINESET_TYPE == "infra" ]];then
        cat /tmp/machineset.json | jq '.spec.template.spec.metadata.labels."node-role.kubernetes.io/infra" = ""' | oc create -f -
    elif [[ $MACHINESET_TYPE == "workload" ]];then
        cat /tmp/machineset.json | jq '.spec.template.spec.metadata.labels."node-role.kubernetes.io/workload" = ""' | oc create -f -
    else
        echo "No support label type, please check ..."
        exit 1
    fi
    # Scale machineset to expected number of replicas
    oc -n openshift-machine-api scale machineset/"${machineset_name}" --replicas="${NODE_REPLICAS}"

    echo "Waiting for ${MACHINESET_TYPE} nodes to come up"
    retries=0
    attempts=180
    while [[ $(oc -n openshift-machine-api get machineset/${machineset_name} -o 'jsonpath={.status.readyReplicas}') != "${NODE_REPLICAS}" ]];
    do 
        ((retries += 1))
        echo -n "." && sleep 10;
        if [[ ${retries} -gt ${attempts} ]]; then
            echo -e "\n\nError: infra nodes didn't become READY in time, failing, please check"
            print_node_machine_info ${MACHINESET_TYPE}
            exit 1
        fi 
        
    done

    # Collect infra node names
    mapfile -t INFRA_NODE_NAMES < <(echo "$(oc get nodes -l node-role.kubernetes.io/${MACHINESET_TYPE} -o name)" | sed 's;node\/;;g')
    echo -e "\n___________________________________________________________________________________________"
    echo
    echo "${MACHINESET_TYPE} nodes ${INFRA_NODE_NAMES[*]} are up"
    # this infra node will not be managed by any default MCP after removing the default worker role,
    # it will leads to some configs cannot be applied to this infra node, such as, ICSP, details: https://issues.redhat.com/browse/OCPBUGS-10596
    oc label nodes --overwrite -l "node-role.kubernetes.io/${MACHINESET_TYPE}=" node-role.kubernetes.io/worker-
    echo
    echo "###########################################################################################"
    oc get machineset -A
    oc get machines -A
    oc get nodes -l node-role.kubernetes.io/${MACHINESET_TYPE}
    echo "###########################################################################################"
}

function create_machineconfigpool()
{
  #MACHINESET_TYPE -- infra or workload machineset
  MACHINESET_TYPE=$1
  MACHINESET_TYPE=$(echo $MACHINESET_TYPE | tr -s [A-Z] [a-z])
  MACHINESET_TYPE=${MACHINESET_TYPE:-infra}
  # Create infra machineconfigpool
  if [[ $MACHINESET_TYPE == "infra" ]];then
      oc get mcp |grep infra
      if [[ $? -ne 0 ]];then
      oc create -f - <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: infra
  labels:
    operator.machineconfiguration.openshift.io/required-for-upgrade: ''
spec:
  machineConfigSelector:
    matchExpressions:
      - {key: machineconfiguration.openshift.io/role, operator: In, values: [worker,infra]}
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/infra: ""
EOF
     fi
 elif [[ $MACHINESET_TYPE == "workload" ]];then
      oc get mcp |grep workload
      if [[ $? -ne 0 ]];then
      oc create -f - <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: workload
  labels:
    operator.machineconfiguration.openshift.io/required-for-upgrade: ''
spec:
  machineConfigSelector:
    matchExpressions:
      - {key: machineconfiguration.openshift.io/role, operator: In, values: [worker,workload]}
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/workload: ""
EOF
     fi
 else
     echo "Invalid machineset type, should be [infra] or [workload]"
 fi
}

function check_monitoring_statefulset_status()
{
  attempts=20
  infra_nodes=$(oc get nodes -l 'node-role.kubernetes.io/infra=' --no-headers | awk '{print $1}' |  tr '\n' '|')
  #infra_nodes=${infra_nodes:0:-1}
  echo "$infra_nodes"
  ## need to get number of runnig pods in statefulsets 
  for statefulset in $(oc get statefulsets --no-headers -n openshift-monitoring | awk '{print $1}'); do
    ready_replicas=$(oc get statefulsets $statefulset -n openshift-monitoring -o jsonpath='{.status.availableReplicas}')
    wanted_replicas=$(oc get statefulsets $statefulset -n openshift-monitoring "-ojsonpath="{.spec.replicas}"")
    retries=0
    monitoring_pods=$(oc get pods -n openshift-monitoring --no-headers -o wide | grep -E "$infra_nodes"| grep "$statefulset")
    infra_pods=$(oc get pods -n openshift-monitoring --no-headers -o wide | grep -E "$infra_nodes" | grep Running | grep "$statefulset" | wc -l  | xargs)
    echo
    echo "-------------------------------------------------------------------------------------------"
    echo "current replicas in $statefulset: wanted--$wanted_replicas, current ready--$ready_replicas!"
    echo "current replicas in $statefulset: wanted--$wanted_replicas, current infra running--$infra_pods!"
    while [[ $ready_replicas != $wanted_replicas ]] ||  [[ $infra_pods != $wanted_replicas ]]; do
        sleep 30
        ((retries += 1))
        ready_replicas=$(oc get statefulsets $statefulset -n openshift-monitoring -o jsonpath='{.status.availableReplicas}')
        echo "retries printing: $retries"
        monitoring_pods=$(oc get pods -n openshift-monitoring --no-headers -o wide | grep -E "$infra_nodes"| grep "$statefulset")
        echo "pods $monitoring_pods"

        infra_pods=$(oc get pods -n openshift-monitoring --no-headers -o wide | grep -E "$infra_nodes" | grep Running| grep "$statefulset" | wc -l |xargs )
        echo
        echo "-------------------------------------------------------------------------------------------"
        echo "current replicas in $statefulset: wanted--$wanted_replicas, current ready--$ready_replicas!"
        echo "current replicas in $statefulset: wanted--$wanted_replicas, current infra running--$infra_pods!"
        if [[ ${retries} -gt ${attempts} ]]; then
            echo "-------------------------------------------------------------------------------------------"
            oc describe statefulsets $statefulset -n openshift-monitoring
            for pod in $(oc get pods -n openshift-monitoring --no-headers | grep -v Running | awk '{print $1}'); do
                oc describe pod $pod -n openshift-monitoring
            done
            echo "error: monitoring statefulsets/pods didn't become Running in time, failing"
            exit 1
        fi
    done
    echo
  done
  if [[ ${retries} -lt ${attempts} ]]; then
    echo "All statefulset is running in openshift-monitoring as expected"
  fi
}

function move_routers_ingress(){
echo "===Moving routers ingress pods to infra nodes==="
oc patch -n openshift-ingress-operator ingresscontrollers.operator.openshift.io default -p '{"spec": {"nodePlacement": {"nodeSelector": {"matchLabels": {"node-role.kubernetes.io/infra": ""}}}}}' --type merge
oc rollout status deployment router-default -n openshift-ingress
# Collect infra node names
mapfile -t INFRA_NODE_NAMES < <(echo "$(oc get nodes -l node-role.kubernetes.io/infra -o name)" | sed 's;node\/;;g')

INGRESS_PODS_MOVED="false"
for i in $(seq 0 60); do
  echo "Checking ingress pods, attempt ${i}"
  mapfile -t INGRESS_NODES < <(oc get pods -n openshift-ingress -o jsonpath='{.items[*].spec.nodeName}')
   TOTAL_NODEPOOL=$(echo "${INGRESS_NODES[@]}" "${INFRA_NODE_NAMES[@]}" | tr ' ' '\n' | sort | uniq -u)
   echo 
   echo "Move the pod that running out of infra node into infra node"
   echo "---------------------------------------------------------------------------------"
   echo -e "Move:\nPOD IP: [ ${INGRESS_NODES[@]} ]"
   echo -e "To: \nInfra Node IP[ ${INFRA_NODE_NAMES[@]} ]"
   if [[ -z ${TOTAL_NODEPOOL} || $(echo $TOTAL_NODEPOOL |tr ' ' '\n'|wc -l) -lt 3 ]]; then
      INGRESS_PODS_MOVED="true"
      echo "Ingress pods moved to infra nodes"
      echo "---------------------------------------------------------------------------------"
      oc get po -o wide -n openshift-ingress |grep router-default 
      echo "---------------------------------------------------------------------------------"
      break
  else
    sleep 10
  fi
done
if [[ "${INGRESS_PODS_MOVED}" == "false" ]]; then
  echo "Ingress pods didn't move to infra nodes"
  exit 1
fi
echo
}

function move_registry(){
echo "====Moving registry pods to infra nodes===="
oc apply -f - <<EOF
apiVersion: imageregistry.operator.openshift.io/v1
kind: Config 
metadata:
  name: cluster
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          namespaces:
          - openshift-image-registry
          topologyKey: kubernetes.io/hostname
        weight: 100
  nodeSelector:
    node-role.kubernetes.io/infra: ""
  tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/infra
    value: reserved
  - effect: NoExecute
    key: node-role.kubernetes.io/infra
    value: reserved 
EOF
oc rollout status deployment image-registry -n openshift-image-registry
REGISTRY_PODS_MOVED="false"
for i in $(seq 0 60); do
  echo "Checking registry pods, attempt ${i}"
  mapfile -t REGISTRY_NODES < <(oc get pods -n openshift-image-registry -l docker-registry=default -o jsonpath='{.items[*].spec.nodeName}')
   TOTAL_NODEPOOL=$(echo "${REGISTRY_NODES[@]}" "${INFRA_NODE_NAMES[@]}" | tr ' ' '\n' | sort | uniq -u)
   echo 
   echo "Move the pod that running out of infra node into infra node"
   echo "---------------------------------------------------------------------------------"
   echo -e "Move:\nPOD IP: [ ${REGISTRY_NODES[@]} ]"
   echo -e "To: \nInfra Node IP[ ${INFRA_NODE_NAMES[@]} ]"
   if [[ -z ${TOTAL_NODEPOOL} || $(echo $TOTAL_NODEPOOL |tr ' ' '\n'|wc -l) -lt 3 ]]; then
      REGISTRY_PODS_MOVED="true"
      echo "Registry pods moved to infra nodes"
      echo "---------------------------------------------------------------------------------"
      oc get po -o wide -n openshift-image-registry | egrep ^image-registry
      echo "---------------------------------------------------------------------------------"
      break
  else
      sleep 10
  fi
done
if [[ "${REGISTRY_PODS_MOVED}" == "false" ]]; then
  echo "Image registry pods didn't move to infra nodes"
  exit 1
fi
echo
}

function move_monitoring(){
echo "===Moving monitoring pods to infra nodes==="

platform_type=$(oc get infrastructure cluster -o=jsonpath={.status.platformStatus.type})
platform_type=$(echo $platform_type | tr -s 'A-Z' 'a-z')

default_sc=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
if [[ -n $default_sc ]]; then
    set_storage_class
    envsubst < monitoring-config.yaml | oc apply -f -
else
    envsubst < monitoring-config-no-pvc.yaml | oc apply -f -
fi

sleep 30
MONITORING_PODS_MOVED="false"
for i in $(seq 0 60); do

   echo "Checking monitoring pods, attempt ${i}"
   MONITORING_NODES=(`oc get pods -n openshift-monitoring -o jsonpath='{.items[*].spec.nodeName}' -l app.kubernetes.io/component=alert-router`)
   MONITORING_NODES+=(`oc get pods -n openshift-monitoring -o jsonpath='{.items[*].spec.nodeName}' -l app.kubernetes.io/name=kube-state-metrics`)
   MONITORING_NODES+=(`oc get pods -n openshift-monitoring -o jsonpath='{.items[*].spec.nodeName}' -l app.kubernetes.io/name=prometheus-adapter`)
   MONITORING_NODES+=(`oc get pods -n openshift-monitoring -o jsonpath='{.items[*].spec.nodeName}' -l app.kubernetes.io/name=prometheus`)
   MONITORING_NODES+=(`oc get pods -n openshift-monitoring -o jsonpath='{.items[*].spec.nodeName}' -l app.kubernetes.io/name=prometheus-operator`)
   MONITORING_NODES+=(`oc get pods -n openshift-monitoring -o jsonpath='{.items[*].spec.nodeName}' -l app.kubernetes.io/name=prometheus-operator-admission-webhook`)
   MONITORING_NODES+=(`oc get pods -n openshift-monitoring -o jsonpath='{.items[*].spec.nodeName}' -l app.kubernetes.io/name=telemeter-client`)
   MONITORING_NODES+=(`oc get pods -n openshift-monitoring -o jsonpath='{.items[*].spec.nodeName}' -l app.kubernetes.io/name=thanos-query`)
   TOTAL_NODEPOOL=$(echo "${MONITORING_NODES[@]}" "${INFRA_NODE_NAMES[@]}" | tr ' ' '\n' | sort | uniq -u)
   echo 
   echo "Move the pod that running out of infra node into infra node"
   echo "---------------------------------------------------------------------------------"
   echo -e "Move:\nPOD IP: [ ${MONITORING_NODES[@]} ]"
   echo -e "To: \nInfra Node IP[ ${INFRA_NODE_NAMES[@]} ]"
   if [[ -z ${TOTAL_NODEPOOL} || $(echo $TOTAL_NODEPOOL |tr ' ' '\n'|wc -l) -lt 3 ]]; then
      MONITORING_PODS_MOVED="true"
      echo "Monitoring pods moved to infra nodes"
      break
  else
    sleep 10
  fi
done
if [[ "${MONITORING_PODS_MOVED}" == "false" ]]; then
  echo "Monitoring pods didn't move to infra nodes"
  exit 1
fi


check_monitoring_statefulset_status

echo "Final check - Check if all pods to be settle"
sleep 5
max_retries=30
retry_times=1
while [[ $(oc get pods --no-headers -n openshift-monitoring | grep -Pv "(Completed|Running)" | wc -l) != "0" ]];
do
    echo -n "." && sleep 5; 
    if [[ $retry_times -le $max_retries ]];then
       echo "Some pods fail to startup in limit times, please check ..."
       exit 1
    fi
    retry_times=$(( $retry_times + 1 ))
done
if [[ $retry_times -lt $max_retries ]];then
echo "######################################################################################"
echo "#                 All PODs of prometheus is Completed or Running!                    #"
echo "######################################################################################"
fi
echo
wait_for_prometheus_status
}
