#!/usr/bin/env bash

SCRIPTS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
export DEFAULT_SC=$(oc get storageclass -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
#export KUBECONFIG=~/.kube/config
deploy_netobserv() {
  echo "====> Deploying NetObserv"
  if [[ -z $INSTALLATION_SOURCE ]]; then
    echo "Please set INSTALLATION_SOURCE env variable to either 'Official', 'Internal', 'OperatorHub', or 'Source' if you intend to use the 'deploy_netobserv' function"
    echo "Don't forget to source 'netobserv.sh' again after doing so!"
    exit 1
  elif [[ $INSTALLATION_SOURCE == "Official" ]]; then
    echo "Using 'Official' as INSTALLATION_SOURCE"
    NOO_SUBSCRIPTION=netobserv-official-subscription.yaml
  elif [[ $INSTALLATION_SOURCE == "Internal" ]]; then
    echo "Using 'Internal' as INSTALLATION_SOURCE"
    NOO_SUBSCRIPTION=netobserv-internal-subscription.yaml
    deploy_unreleased_catalogsource
  elif [[ $INSTALLATION_SOURCE == "OperatorHub" ]]; then
    echo "Using 'OperatorHub' as INSTALLATION_SOURCE"
    NOO_SUBSCRIPTION=netobserv-operatorhub-subscription.yaml
  elif [[ $INSTALLATION_SOURCE == "Source" ]]; then
    echo "Using 'Source' as INSTALLATION_SOURCE"
    NOO_SUBSCRIPTION=netobserv-source-subscription.yaml
    deploy_main_catalogsource
  else
    echo "'$INSTALLATION_SOURCE' is not a valid value for INSTALLATION_SOURCE"
    echo "Please set INSTALLATION_SOURCE env variable to either 'Official', 'Internal', 'OperatorHub', or 'Source' if you intend to use the 'deploy_netobserv' function"
    echo "Don't forget to source 'netobserv.sh' again after doing so!"
    exit 1
  fi

  echo "====> Creating NetObserv Project (if it does not already exist)"
  oc new-project netobserv || true

  echo "====> Checking if LokiStack prerequisite has been satisfied"
  oc wait --timeout=300s --for=condition=ready pod -l app.kubernetes.io/name=lokistack -n netobserv

  echo "====> Creating openshift-netobserv-operator namespace and OperatorGroup"
  oc apply -f $SCRIPTS_DIR/netobserv/netobserv-ns_og.yaml
  echo "====> Creating NetObserv subscription"
  oc apply -f $SCRIPTS_DIR/netobserv/$NOO_SUBSCRIPTION
  sleep 60
  oc wait --timeout=180s --for=condition=ready pod -l app=netobserv-operator -n openshift-netobserv-operator
  while :; do
    oc get crd/flowcollectors.flows.netobserv.io && break
    sleep 1
  done

  echo "====> Patch CSV so that DOWNSTREAM_DEPLOYMENT is set to 'true'"
  CSV=$(oc get csv -n openshift-netobserv-operator | egrep -i "net.*observ" | awk '{print $1}')
  oc patch csv/$CSV -n openshift-netobserv-operator --type=json -p "[{"op": "replace", "path": "/spec/install/spec/deployments/0/spec/template/spec/containers/0/env/3/value", "value": 'true'}]"

  echo "====> Creating Flow Collector"
  oc apply -f $SCRIPTS_DIR/netobserv/flows_v1beta2_flowcollector.yaml

  echo "====> Waiting for flowlogs-pipeline pods to be ready"
  while :; do
    oc get daemonset flowlogs-pipeline -n netobserv && break
    sleep 1
  done
  sleep 60
  oc wait --timeout=1200s --for=condition=ready pod -l app=flowlogs-pipeline -n netobserv
}

patch_netobserv() {
  COMPONENT=$1
  IMAGE=$2
  CSV=$(oc get csv -n openshift-netobserv-operator | egrep -i "net.*observ" | awk '{print $1}')
  if [[ -z "$COMPONENT" || -z "$IMAGE" ]]; then
    echo "Specify COMPONENT and IMAGE to be patched to existing CSV deployed"
    exit 1
  fi

  if [[ "$COMPONENT" == "ebpf" ]]; then
    echo "====> Patching eBPF image"
    PATCH="[{\"op\": \"replace\", \"path\": \"/spec/install/spec/deployments/0/spec/template/spec/containers/0/env/0/value\", \"value\": \"$IMAGE\"}]"
  elif [[ "$COMPONENT" == "flp" ]]; then
    echo "====> Patching FLP image"
    PATCH="[{\"op\": \"replace\", \"path\": \"/spec/install/spec/deployments/0/spec/template/spec/containers/0/env/1/value\", \"value\": \"$IMAGE\"}]"
  elif [[ "$COMPONENT" == "plugin" ]]; then
    echo "====> Patching Plugin image"
    PATCH="[{\"op\": \"replace\", \"path\": \"/spec/install/spec/deployments/0/spec/template/spec/containers/0/env/2/value\", \"value\": \"$IMAGE\"}]"
  else
    echo "Use component ebpf, flp, plugin, operator as component to patch or to have metrics populated for upstream installation to cluster prometheus"
    exit 1
  fi

  oc patch csv/$CSV -n openshift-netobserv-operator --type=json -p="$PATCH"

  if [[ $? != 0 ]]; then
    echo "failed to patch $COMPONENT with $IMAGE"
    exit 1
  fi
}

deploy_lokistack() {
  echo "====> Deploying LokiStack"
  echo "====> Creating NetObserv Project (if it does not already exist)"
  oc new-project netobserv || true

  echo "====> Creating openshift-operators-redhat Namespace and OperatorGroup"
  oc apply -f $SCRIPTS_DIR/loki/loki-operatorgroup.yaml

  echo "====> Creating qe-unreleased-testing CatalogSource (if applicable) and Loki Operator Subscription"
  if [[ $LOKI_OPERATOR == "Released" ]]; then
    oc apply -f $SCRIPTS_DIR/loki/loki-released-subscription.yaml
  elif [[ $LOKI_OPERATOR == "Unreleased" ]]; then
    deploy_unreleased_catalogsource
    oc apply -f $SCRIPTS_DIR/loki/loki-unreleased-subscription.yaml
  else
    echo "====> No Loki Operator config was found - using 'Released'"
    echo "====> To set config, set LOKI_OPERATOR variable to either 'Released' or 'Unreleased'"
    oc apply -f $SCRIPTS_DIR/loki/loki-released-subscription.yaml
  fi

  echo "====> Generate S3_BUCKET_NAME"
  RAND_SUFFIX=$(tr </dev/urandom -dc 'a-z0-9' | fold -w 6 | head -n 1 || true)
  if [[ $WORKLOAD == "None" ]] || [[ -z $WORKLOAD ]]; then
    export S3_BUCKET_NAME="netobserv-ocpqe-$USER-$RAND_SUFFIX"
  else
    export S3_BUCKET_NAME="netobserv-ocpqe-$USER-$WORKLOAD-$RAND_SUFFIX"
  fi

  # if cluster is to be preserved, do the same for S3 bucket
  CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
  if [[ $CLUSTER_NAME =~ "preserve" ]]; then
    S3_BUCKET_NAME+="-preserve"
  fi
  echo "====> S3_BUCKET_NAME is $S3_BUCKET_NAME"

  echo "====> Creating S3 secret for Loki"
  $SCRIPTS_DIR/deploy-loki-aws-secret.sh $S3_BUCKET_NAME
  sleep 60
  oc wait --timeout=180s --for=condition=ready pod -l app.kubernetes.io/name=loki-operator -n openshift-operators-redhat

  echo "====> Determining LokiStack config"
  if [[ $LOKISTACK_SIZE == "1x.extra-small" ]]; then
    LokiStack_CONFIG=$SCRIPTS_DIR/loki/lokistack-1x-exsmall.yaml
  elif [[ $LOKISTACK_SIZE == "1x.small" ]]; then
    LokiStack_CONFIG=$SCRIPTS_DIR/loki/lokistack-1x-small.yaml
  elif [[ $LOKISTACK_SIZE == "1x.medium" ]]; then
    LokiStack_CONFIG=$SCRIPTS_DIR/loki/lokistack-1x-medium.yaml
  else
    echo "====> No LokiStack config was found - using '1x.extra-small'"
    echo "====> To set config, set LOKISTACK_SIZE variable to either '1x.extra-small', '1x.small', or '1x.medium'"
    LokiStack_CONFIG=$SCRIPTS_DIR/loki/lokistack-1x-exsmall.yaml
  fi
  TMP_LOKICONFIG=/tmp/lokiconfig.yaml
  envsubst <$LokiStack_CONFIG >$TMP_LOKICONFIG

  echo "====> Creating LokiStack"
  oc apply -f $TMP_LOKICONFIG
  sleep 30
  oc wait --timeout=300s --for=condition=ready pod -l app.kubernetes.io/name=lokistack -n netobserv

  echo "====> Configuring Loki rate limit alert"
  oc apply -f $SCRIPTS_DIR/loki/loki-ratelimit-alert.yaml
}

deploy_unreleased_catalogsource() {
  echo "====> Creating brew-registry ImageContentSourcePolicy"
  oc apply -f $SCRIPTS_DIR/icsp.yaml

  echo "====> Determining CatalogSource config"
  if [[ -z $DOWNSTREAM_IMAGE ]]; then
    echo "====> No image config was found - cannot create CatalogSource"
    echo "====> To set config, set DOWNSTREAM_IMAGE variable to desired endpoint"
    exit 1
  else
    echo "====> Using image $DOWNSTREAM_IMAGE for CatalogSource"
  fi

  CatalogSource_CONFIG=$SCRIPTS_DIR/catalogsources/qe-unreleased-catalogsource.yaml
  TMP_CATALOGCONFIG=/tmp/catalogconfig.yaml
  envsubst <$CatalogSource_CONFIG >$TMP_CATALOGCONFIG

  echo "====> Creating qe-unreleased-testing CatalogSource"
  oc apply -f $TMP_CATALOGCONFIG
  sleep 30
  oc wait --timeout=180s --for=condition=ready pod -l olm.catalogSource=qe-unreleased-testing -n openshift-marketplace
}

deploy_main_catalogsource() {
  echo "====> Determining CatalogSource config"
  if [[ -z $UPSTREAM_IMAGE ]]; then
    echo "====> No image config was found - using main"
    echo "====> To set config, set UPSTREAM_IMAGE variable to desired endpoint"
    export UPSTREAM_IMAGE="quay.io/netobserv/network-observability-operator-catalog:v0.0.0-main"
  else
    echo "====> Using image $UPSTREAM_IMAGE for CatalogSource"
  fi

  CatalogSource_CONFIG=$SCRIPTS_DIR/catalogsources/netobserv-main-catalogsource.yaml
  TMP_CATALOGCONFIG=/tmp/catalogconfig.yaml
  envsubst <$CatalogSource_CONFIG >$TMP_CATALOGCONFIG

  echo "====> Creating netobserv-main-testing CatalogSource from the main bundle"
  oc apply -f $TMP_CATALOGCONFIG
  sleep 30
  oc wait --timeout=180s --for=condition=ready pod -l olm.catalogSource=netobserv-main-testing -n openshift-marketplace
}

deploy_kafka() {
  BROKER_REPLICAS=${BROKER_REPLICAS:=3}
  export DEFAULT_SC=$(oc get storageclass -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
  echo "====> Deploying Kafka"
  oc create namespace netobserv --dry-run=client -o yaml | oc apply -f -
  echo "====> Creating amq-streams Subscription"
  oc apply -f $SCRIPTS_DIR/amq-streams/amq-streams-subscription.yaml
  sleep 60
  oc wait --timeout=180s --for=condition=ready pod -l name=amq-streams-cluster-operator -n openshift-operators
  echo "====> Creating kafka-metrics ConfigMap and kafka-resources-metrics PodMonitor"
  oc apply -f "https://raw.githubusercontent.com/netobserv/documents/main/examples/kafka/metrics-config.yaml" -n netobserv
  echo "====> Creating kafka-cluster Kafka"
  #curl -s -L "https://raw.githubusercontent.com/netobserv/documents/main/examples/kafka/default.yaml" | envsubst | oc apply -n netobserv -f -
  
  oc -n netobserv apply -f-<<EOF
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: kafka-cluster
spec:
  kafka:
    replicas: ${BROKER_REPLICAS}
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
      - name: external
        port: 9094
        type: nodeport
        tls: false
    config:
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
      min.insync.replicas: 1
      auto.create.topics.enable: false
      log.cleaner.backoff.ms: 15000
      log.cleaner.dedupe.buffer.size: 134217728
      log.cleaner.enable: true
      log.cleaner.io.buffer.load.factor: 0.9
      log.cleaner.threads: 8
      log.cleanup.policy: delete
      log.retention.bytes: 107374182400
      log.retention.check.interval.ms: 300000
      log.retention.ms: 1680000
      log.roll.ms: 7200000
      log.segment.bytes: 1073741824
    storage:
      type: persistent-claim
      size: 200Gi
      class: ${DEFAULT_SC}
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: kafka-metrics-config.yml
  zookeeper:
    replicas: 3
    storage:
      type: persistent-claim
      size: 20Gi
      class: ${DEFAULT_SC}
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: zookeeper-metrics-config.yml
  entityOperator:
    topicOperator: {}
    userOperator: {}
EOF

  echo "====> Creating network-flows KafkaTopic"
  if [[ -z $TOPIC_PARTITIONS ]]; then
    echo "====> No topic partitions config was found - using 6"
    echo "====> To set config, set TOPIC_PARTITIONS variable to desired number"
    export TOPIC_PARTITIONS=6
  fi  
  KAFKA_TOPIC=$SCRIPTS_DIR/amq-streams/kafkaTopic.yaml
  TMP_KAFKA_TOPIC=/tmp/topic.yaml
  envsubst <$KAFKA_TOPIC >$TMP_KAFKA_TOPIC
  oc apply -f $TMP_KAFKA_TOPIC -n netobserv
  sleep 60
  oc wait --timeout=180s --for=condition=ready kafkatopic network-flows -n netobserv 
}

 update_flowcollector_use_kafka_deploymentModel(){
  echo "====> Update flowcollector to use Kafka deploymentModel"
  oc patch flowcollector cluster --type=json -p "[{"op": "replace", "path": "/spec/deploymentModel", "value": "Kafka"}]"

  echo "====> Update flowcollector replicas"
  if [[ -z $FLP_KAFKA_REPLICAS ]]; then
    echo "====> No flowcollector replicas config was found - using '3'"
    echo "====> To set config, set FLP_KAFKA_REPLICAS variable to desired number"
    FLP_KAFKA_REPLICAS=3
  fi
  oc patch flowcollector/cluster --type=json -p "[{"op": "replace", "path": "/spec/processor/kafkaConsumerReplicas", "value": $FLP_KAFKA_REPLICAS}]"

  echo "====> Waiting for Flow Collector to reload with new FLP pods..."
  oc wait --timeout=180s --for=condition=ready flowcollector/cluster
 }

delete_s3() {
  echo "====> Getting S3 Bucket Name"
  S3_BUCKET_NAME=$(/bin/bash -c 'oc extract cm/lokistack-config -n netobserv --keys=config.yaml --confirm --to=/tmp | xargs -I {} egrep bucketnames {} | cut -d: -f 2 | xargs echo -n')
  if [[ -z $S3_BUCKET_NAME ]]; then
    echo "====> Could not get S3 Bucket Name"
  else
    echo "====> Got $S3_BUCKET_NAME"
    echo "====> Deleting AWS S3 Bucket"
    while :; do
      aws s3 rb s3://$S3_BUCKET_NAME --force && break
      sleep 1
    done
    echo "====> AWS S3 Bucket $S3_BUCKET_NAME deleted"
  fi
}

delete_lokistack() {
  echo "====> Deleting LokiStack"
  oc delete --ignore-not-found lokistack/lokistack -n netobserv
}

delete_kafka() {
  echo "====> Deleting Kafka (if applicable)"
  echo "====> Getting Deployment Model"
  DEPLOYMENT_MODEL=$(oc get flowcollector -o jsonpath='{.items[*].spec.deploymentModel}' -n netobserv)
  echo "====> Got $DEPLOYMENT_MODEL"
  if [[ $DEPLOYMENT_MODEL == "Kafka" ]]; then
    oc delete --ignore-not-found kafka/kafka-cluster -n netobserv
    oc delete --ignore-not-found kafkaTopic/network-flows -n netobserv
    oc delete --ignore-not-found -f $SCRIPTS_DIR/amq-streams/amq-streams-subscription.yaml
    oc delete --ignore-not-found csv -l operators.coreos.com/amq-streams.openshift-operators -n openshift-operators
  fi
}

delete_flowcollector() {
  echo "====> Deleting Flow Collector"
  # note 'cluster' is the default Flow Collector name, but that may not always be the case
  oc delete --ignore-not-found flowcollector/cluster
}

delete_netobserv_operator() {
  echo "====> Deleting all NetObserv resources"
  oc delete --ignore-not-found -f $SCRIPTS_DIR/netobserv/netobserv-official-subscription.yaml
  oc delete --ignore-not-found -f $SCRIPTS_DIR/netobserv/netobserv-internal-subscription.yaml
  oc delete --ignore-not-found -f $SCRIPTS_DIR/netobserv/netobserv-operatorhub-subscription.yaml
  oc delete --ignore-not-found -f $SCRIPTS_DIR/netobserv/netobserv-source-subscription.yaml
  oc delete --ignore-not-found csv -l operators.coreos.com/netobserv-operator.openshift-netobserv-operator= -n openshift-netobserv-operator
  oc delete --ignore-not-found crd/flowcollectors.flows.netobserv.io
  oc delete --ignore-not-found -f $SCRIPTS_DIR/netobserv/netobserv-ns_og.yaml
  echo "====> Deleting netobserv-main-testing and qe-unreleased-testing CatalogSource (if applicable)"
  oc delete --ignore-not-found catalogsource/netobserv-main-testing -n openshift-marketplace
  oc delete --ignore-not-found catalogsource/qe-unreleased-testing -n openshift-marketplace
}

delete_loki_operator() {
  echo "====> Deleting Loki Operator Subscription and CSV"
  oc delete --ignore-not-found -f $SCRIPTS_DIR/loki/loki-released-subscription.yaml
  oc delete --ignore-not-found -f $SCRIPTS_DIR/loki/loki-unreleased-subscription.yaml
  oc delete --ignore-not-found csv -l operators.coreos.com/loki-operator.openshift-operators-redhat -n openshift-operators-redhat
}

nukeobserv() {
  echo "====> Nuking NetObserv and all related resources"
  delete_s3
  delete_lokistack
  delete_kafka
  delete_flowcollector
  delete_netobserv_operator
  delete_loki_operator
  # seperate step as multiple different operators use this namespace
  oc delete project netobserv
}

deploy-xk6-kafka (){
  SCRIPTS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
  #git clone https://github.com/mostafa/xk6-kafka.git
  cd $SCRIPTS_DIR/xk6-kafka
  oc -n netobserv create configmap xk6-kafka-scripts --from-file=scripts/
  oc -n netobserv apply -f-<<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: xk6-kafka
  name: xk6-kafka
spec:
  replicas: 1
  selector:
    matchLabels:
      app: xk6-kafka
  template:
    metadata:
      labels:
        app: xk6-kafka
    spec:
      nodeSelector:
        node-role.kubernetes.io/workload: ""
      containers:
      - image: mostafamoradian/xk6-kafka:latest 
        name: xk6-kafka
        imagePullPolicy: Always
            #command: [ "k6", "run", "--vus","50","--duration","3600","scripts/test_json.js"] 
        command: ["k6","run","-u","50","-d","60m","/scripts/test_json.js"]
        env: 
          - name: KAFKA_SERVICE
            value: kafka-services
          - name: VIRTUAL_USERS
            value: "50"
        volumeMounts:
          - mountPath: /scripts/
            name: xk6-kafka-scripts
            #subPath: status.html
      volumes:
        - name: xk6-kafka-scripts
          configMap: 
            name: xk6-kafka-scripts  
EOF
}