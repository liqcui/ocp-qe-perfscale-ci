@Library('flexy') _

// rename build
def userCause = currentBuild.rawBuild.getCause(Cause.UserIdCause)
def upstreamCause = currentBuild.rawBuild.getCause(Cause.UpstreamCause)

userId = "ocp-perfscale-qe"
if (userCause) {
    userId = userCause.getUserId()
}
else if (upstreamCause) {
    def upstreamJob = Jenkins.getInstance().getItemByFullName(upstreamCause.getUpstreamProject(), hudson.model.Job.class)
    if (upstreamJob) {
        def upstreamBuild = upstreamJob.getBuildByNumber(upstreamCause.getUpstreamBuild())
        if (upstreamBuild) {
            def realUpstreamCause = upstreamBuild.getCause(Cause.UserIdCause)
            if (realUpstreamCause) {
                userId = realUpstreamCause.getUserId()
            }
        }
    }
}
if (userId) {
    currentBuild.displayName = userId
}


def JENKINS_JOB_NUMBER = currentBuild.number.toString()
println "JENKINS_JOB_NUMBER $JENKINS_JOB_NUMBER"

println "user id $userId"
def RETURNSTATUS = "default"
def output = ""
def cerberus_job = ""
def status = "FAIL"
pipeline {
  agent none
  parameters {
      string(
          name: 'BUILD_NUMBER',
          defaultValue: '',
          description: 'Build number of job that has installed the cluster.'
      )
      choice(
          name: 'WORKLOAD',
          choices: ["cluster-density", "cluster-density-v2", "node-density", "node-density-heavy","node-density-cni"],
          description: 'Type of kube-burner job to run'
      )
      booleanParam(
          name: 'WRITE_TO_FILE',
          defaultValue: false,
          description: 'Value to write to google sheet (will run <a href=https://mastern-jenkins-csb-openshift-qe.apps.ocp-c1.prod.psi.redhat.com/job/scale-ci/job/e2e-benchmarking-multibranch-pipeline/job/write-scale-ci-results>write-scale-ci-results</a>)'
      )
      booleanParam(
          name: 'WRITE_TO_ES',
          defaultValue: false,
          description: 'Value to write to elastic seach under metricName: jenkinsEnv'
      )
      booleanParam(
          name: 'CLEANUP',
          defaultValue: false,
          description: 'Cleanup namespaces (and all sub-objects) created from workload (will run <a href=https://mastern-jenkins-csb-openshift-qe.apps.ocp-c1.prod.psi.redhat.com/job/scale-ci/job/e2e-benchmarking-multibranch-pipeline/job/benchmark-cleaner/>benchmark-cleaner</a>)'
      )
      booleanParam(
          name: 'CERBERUS_CHECK',
          defaultValue: false,
          description: 'Check cluster health status pass (will run <a href=https://mastern-jenkins-csb-openshift-qe.apps.ocp-c1.prod.psi.redhat.com/job/scale-ci/job/e2e-benchmarking-multibranch-pipeline/job/cerberus/>cerberus</a>)'
      )
      booleanParam(
            name: 'MUST_GATHER', 
            defaultValue: true, 
            description: 'This variable will run must-gather if any cerberus components fail'
        )
      string(
          name: 'IMAGE_STREAM', 
          defaultValue: 'openshift/must-gather', 
          description: 'Base image stream of data to gather for the must-gather.'
        )
        string(
          name: 'IMAGE', 
          defaultValue: '', 
          description: 'Optional image to help get must-gather information on non default areas. See <a href="https://docs.openshift.com/container-platform/4.12/support/gathering-cluster-data.html">docs</a> for more information and options.'
        )
      booleanParam(
          name: 'CHURN',
          defaultValue: false,
          description: '''Run churn at end of original iterations. <a href=https://github.com/cloud-bulldozer/e2e-benchmarking/tree/master/workloads/kube-burner#churn>Churning</a> allows you to scale down and then up a percentage of JOB_ITERATIONS after the objects have been created <br>
          Use the following variables in ENV_VARS to set specifics of churn. Otherwise the below will run as default <br>
          CHURN_DURATION=10m  <br>
          CHURN_PERCENT=10 <br>
          CHURN_DELAY=60s'''
      )
      string(
          name: 'VARIABLE',
          defaultValue: '1000', 
          description: '''
          This variable configures parameter needed for each type of workload. By default 1000.<br>
          cluster-density: This will export JOB_ITERATIONS env variable, set to 9 * num_workers. This variable sets the number of iterations to perform (1 namespace per iteration).<br>
          cluster-density-v2: This will export JOB_ITERATIONS env variable, set to 9 * num_workers. This variable sets the number of iterations to perform (1 namespace per iteration).<br>
          node-density: This will export JOB_ITERATIONS env variable; set to 200, work up to 250. Creates as many "sleep" pods as configured in this variable - existing number of pods on node.<br>
          node-density-heavy: This will export JOB_ITERATIONS env variable; set to 200, work up to 250. Creates this number of applications proportional to the calculated number of pods / 2<br>
          node-density-cni: This will export JOB_ITERATIONS env variable; set to 200, work up to 250. Creates this number of applications proportional to the calculated number of pods / 2<br>
          Read <a href=https://github.com/openshift-qe/ocp-qe-perfscale-ci/tree/kube-burner/README.md>here</a> for details about each variable
          '''
      )
      string(
          name: "COMPARISON_CONFIG",
          defaultValue: "podLatency.json nodeMasters-ocp.json nodeWorkers-ocp.json etcd-ocp.json crio-ocp.json kubelet-ocp.json",
          description: 'JSON config files of what data to output into a Google Sheet'
      )
      string(
          name: "TOLERANCY_RULES",
          defaultValue: "pod-latency-tolerancy-rules.yaml master-tolerancy-ocp.yaml worker-agg-tolerancy-ocp.yaml etcd-tolerancy-ocp.yaml crio-tolerancy-ocp.yaml kubelet-tolerancy-ocp.yaml",
          description: '''JSON config files of what data to compare with and put output into a Google Sheet'''
        )
      booleanParam(
          name: 'GEN_CSV',
          defaultValue: true,
          description: 'Boolean to create a google sheet with comparison data'
      )
      string(
          name: 'EMAIL_ID_OVERRIDE',
          defaultValue: '',
          description: '''
            Email to share Google Sheet results with<br/>
            By default shares with email of person who ran the job
          '''
      )
      string(
          name: 'JENKINS_AGENT_LABEL',
          defaultValue: 'oc415',
          description: '''
            scale-ci-static: for static agent that is specific to scale-ci, useful when the jenkins dynamic agent isn't stable<br>
            4.y: oc4y || mac-installer || rhel8-installer-4y <br/>
                e.g, for 4.8, use oc48 || mac-installer || rhel8-installer-48 <br/>
            3.11: ansible-2.6 <br/>
            3.9~3.10: ansible-2.4 <br/>
            3.4~3.7: ansible-2.4-extra || ansible-2.3 <br/>
            '''
      )
      text(
          name: 'ENV_VARS',
          defaultValue: '',
          description: '''
          Enter list of additional (optional) Env Vars you'd want to pass to the script, one pair on each line.<br>
          e.g.<br>
          SOMEVAR1='env-test'<br>
          SOMEVAR2='env2-test'<br>
          ...<br>
          SOMEVARn='envn-test'<br>
          '''
      )
      booleanParam(
          name: "SEND_SLACK",
          defaultValue: false,
          description: "Check this box to send a Slack notification to #ocp-qe-scale-ci-results upon the job's completion"
      )
      booleanParam(
          name: 'INFRA_WORKLOAD_INSTALL',
          defaultValue: false,
          description: '''
          Install workload and infrastructure nodes even if less than 50 nodes.<br>
          Checking this parameter box is valid only when SCALE_UP is greater than 0.
          '''
      )
      booleanParam(
            name: 'INSTALL_DITTYBOPPER',
            defaultValue: false,
            description: 'Value to install dittybopper dashboards to cluster'
        )
      string(
            name: 'DITTYBOPPER_REPO',
            defaultValue: 'https://github.com/cloud-bulldozer/performance-dashboards.git',
            description: 'You can change this to point to your fork if needed'
        )
      string(
            name: 'DITTYBOPPER_REPO_BRANCH',
            defaultValue: 'master',
            description: 'You can change this to point to a branch on your fork if needed'
        )
      booleanParam(
            name: 'ENABLE_KAFKA',
            defaultValue: false,
            description: 'Check this box to setup Kafka for NetObserv or to update Kafka configs even if it is already installed'
      )
      booleanParam(
            name: 'ENABLE_FLOWCOLLECTOR_KAFKA',
            defaultValue: false,
            description: 'Check this box to config flowcontroller to kafak development mode'
      )
      choice(
            name: 'TOPIC_PARTITIONS',
            choices: [6, 10, 24, 48],
            description: '''
                Number of Kafka Topic Partitions. Below are recommended values for partitions:<br/>
                6 - default for non-perf testing environments<br/>
                10 - Perf testing with worker nodes <= 20<br/>
                24 - Perf testing with worker nodes <= 50<br/>
                48 - Perf testing with worker nodes <= 100<br/>
            '''
      )
      string(
            name: 'FLP_KAFKA_REPLICAS',
            defaultValue: '3',
            description: '''
                Replicas should be at least half the number of Kafka TOPIC_PARTITIONS and should not exceed number of TOPIC_PARTITIONS or number of nodes:<br/>
                3 - default for non-perf testing environments<br/>
            '''
      )
      string(
            name: 'BROKER_REPLICAS',
            defaultValue: '3',
            description: '''
                Replicas of kafka broker:<br/>
                3 - default for non-perf testing environments<br/>
            '''
      )
      choice(
            name: 'LOKI_OPERATOR',
            choices: ['None', 'Released', 'Unreleased'],
            description: '''
                You can use either the latest released or unreleased version of Loki Operator:<br/>
                <b>Released</b> installs the <b>latest released downstream</b> version of the operator, i.e. what is available to customers<br/>
                <b>Unreleased</b> installs the <b>latest unreleased downstream</b> version of the operator, i.e. the most recent internal bundle<br/>
                If <b>None</b> is selected the installation will be skipped
            '''
      )
      choice(
            name: 'LOKISTACK_SIZE',
            choices: ['1x.extra-small', '1x.small', '1x.medium'],
            description: '''
                Depending on size of cluster nodes, use following guidance to choose LokiStack size:<br/>
                1x.extra-small - Nodes size < m6i.4xlarge<br/>
                1x.small - Nodes size >= m6i.4xlarge<br/>
                1x.medium - Nodes size >= m6i.8xlarge<br/>
            '''
      )
      separator(
            name: 'NETOBSERV_CONFIG_OPTIONS',
            sectionHeader: 'Network Observability Configuration Options',
            sectionHeaderStyle: '''
                font-size: 14px;
                font-weight: bold;
                font-family: 'Orienta', sans-serif;
            '''
      )
      choice(
            name: 'INSTALLATION_SOURCE',
            choices: ['None', 'Official', 'Internal', 'OperatorHub', 'Source'],
            description: '''
                Network Observability can be installed from the following sources:<br/>
                <b>Official</b> installs the <b>latest released downstream</b> version of the operator, i.e. what is available to customers<br/>
                <b>Internal</b> installs the <b>latest unreleased downstream</b> version of the operator, i.e. the most recent internal bundle<br/>
                <b>OperatorHub</b> installs the <b>latest released upstream</b> version of the operator, i.e. what is currently available on OperatorHub<br/>
                <b>Source</b> installs the <b>latest unreleased upstream</b> version of the operator, i.e. directly from the main branch of the upstream source code<br/>
                If <b>None</b> is selected the installation will be skipped
            '''
      )
              string(
            name: 'IIB_OVERRIDE',
            defaultValue: '',
            description: '''
                If using Internal installation, you can specify here a specific internal index image to use in the CatalogSource rathar than using the most recent bundle<br/>
                These IDs can be found in CVP emails under 'Index Image Location' section<br/>
                e.g. <b>450360</b>
            '''
        )
        string(
            name: 'OPERATOR_PREMERGE_OVERRIDE',
            defaultValue: '',
            description: '''
                If using Source installation, you can specify here a specific premerge image to use in the CatalogSource rather than using the main branch<br/>
                These SHA hashes can be found in PR's after adding the label '/ok-to-test'<br/>
                e.g. <b>e2bdef6</b>
            '''
        )
        string(
            name: 'FLP_PREMERGE_OVERRIDE',
            defaultValue: '',
            description: '''
                You can specify here a specific FLP premerge image to use rather than using the operator defined image<br/>
                These SHA hashes can be found in FLP PR's after adding the label '/ok-to-test'<br/>
                e.g. <b>e2bdef6</b>
            '''
        )
        string(
            name: 'EBPF_PREMERGE_OVERRIDE',
            defaultValue: '',
            description: '''
                You can specify here a specific eBPF premerge image to use rather than using the operator defined image<br/>
                These SHA hashes can be found in eBPF PR's after adding the label '/ok-to-test'<br/>
                e.g. <b>e2bdef6</b>
            '''
        )
        string(
            name: 'PLUGIN_PREMERGE_OVERRIDE',
            defaultValue: '',
            description: '''
                You can specify here a specific ConsolePlugin premerge image rather than using the operator defined image<br/>
                These SHA hashes can be found in ConsolePlugin PR's after adding the label '/ok-to-test'<br/>
                e.g. <b>e2bdef6</b>
            '''
        )
              string(
            name: 'CONTROLLER_MEMORY_LIMIT',
            defaultValue: '',
            description: 'Note that 800Mi = 800 mebibytes, i.e. 0.8 Gi'
        )
        separator(
            name: 'FLOWCOLLECTOR_CONFIG_OPTIONS',
            sectionHeader: 'Flowcollector Configuration Options',
            sectionHeaderStyle: '''
                font-size: 14px;
                font-weight: bold;
                font-family: 'Orienta', sans-serif;
            '''
        )
        string(
            name: 'EBPF_SAMPLING_RATE',
            defaultValue: '',
            description: 'Rate at which to sample flows'
        )
        string(
            name: 'EBPF_MEMORY_LIMIT',
            defaultValue: '',
            description: 'Note that 800Mi = 800 mebibytes, i.e. 0.8 Gi'
        )
        string(
            name: 'FLP_CPU_LIMIT',
            defaultValue: '',
            description: 'Note that 1000m = 1000 millicores, i.e. 1 core'
        )
        string(
            name: 'FLP_MEMORY_LIMIT',
            defaultValue: '',
            description: 'Note that 800Mi = 800 mebibytes, i.e. 0.8 Gi'
        )
       string(
            name: 'LARGE_SCALE_CLIENTS',
            defaultValue: '1 80',
            description: '''
                Only for <b>router-perf</b><br/>
                Threads/route to use in the large scale scenario
            '''
        )
        string(
            name: 'LARGE_SCALE_CLIENTS_MIX',
            defaultValue: '1 25',
            description: '''
                Only for <b>router-perf</b><br/>
                Threads/route to use in the large scale scenario with mix termination
            '''
        )  
      string(
          name: 'SCALE_UP',
          defaultValue: '0',
          description: 'If value is set to anything greater than 0, cluster will be scaled up before executing the workload.'
      )
      string(
          name: 'SCALE_DOWN',
          defaultValue: '0',
          description: '''
          If value is set to anything greater than 0, cluster will be scaled down after the execution of the workload is complete,<br>
          if the build fails, scale down may not happen, user should review and decide if cluster is ready for scale down or re-run the job on same cluster.
          '''
      )
      string(
          name: 'E2E_BENCHMARKING_REPO',
          defaultValue: 'https://github.com/cloud-bulldozer/e2e-benchmarking',
          description: 'You can change this to point to your fork if needed.'
      )
      string(
          name: 'E2E_BENCHMARKING_REPO_BRANCH',
          defaultValue: 'master',
          description: 'You can change this to point to a branch on your fork if needed.'
      )
  }
  stages {  
    stage('Scale up cluster') {
      agent { label params['JENKINS_AGENT_LABEL'] }
      when {
            expression { params.SCALE_UP.toInteger() > 0 || params.INFRA_WORKLOAD_INSTALL == true}
      }
      steps {
            script {
                build job: 'scale-ci/e2e-benchmarking-multibranch-pipeline/cluster-workers-scaling/',
                    parameters: [
                        string(name: 'BUILD_NUMBER', value: BUILD_NUMBER), text(name: "ENV_VARS", value: ENV_VARS),
                        string(name: 'WORKER_COUNT', value: SCALE_UP), string(name: 'JENKINS_AGENT_LABEL', value: JENKINS_AGENT_LABEL),
                        booleanParam(name: 'INFRA_WORKLOAD_INSTALL', value: INFRA_WORKLOAD_INSTALL)
                    ]
            }
      }
    }
    stage('Install Dittybopper') {
      agent { label params['JENKINS_AGENT_LABEL'] }
      when {
                expression { params.INSTALL_DITTYBOPPER == true }
      }
      steps {
          // checkout performance dashboards repo
          checkout([
                    $class: 'GitSCM',
                    branches: [[name: params.DITTYBOPPER_REPO_BRANCH ]],
                    userRemoteConfigs: [[url: params.DITTYBOPPER_REPO ]],
                    extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'performance-dashboards']]
          ])
          copyArtifacts(
          filter: '',
          fingerprintArtifacts: true,
          projectName: 'ocp-common/Flexy-install',
          selector: specific(params.BUILD_NUMBER),
          target: 'flexy-artifacts'
          )
          script {
                    DITTYBOPPER_PARAMS = "-i $WORKSPACE/scripts/queries/netobserv_dittybopper.json"
                    // attempt installation of dittybopper
                    dittybopperReturnCode = sh(returnStatus: true, script: """
                        if [ ! -d ~/.kube ];then
                           mkdir -p ~/.kube
                        fi
                        cp $WORKSPACE/flexy-artifacts/workdir/install-dir/auth/kubeconfig ~/.kube/config
                        pwd 
                        ls -l
                        find ./ -name netobserv.sh
                        source $WORKSPACE/scripts/netobserv.sh
                        . $WORKSPACE/performance-dashboards/dittybopper/deploy.sh $DITTYBOPPER_PARAMS
                    """)
                    // fail pipeline if installation failed, continue otherwise
                    if (dittybopperReturnCode.toInteger() != 0) {
                        error('Installation of Dittybopper failed :(')
                    }
                    else {
                        println('Successfully installed Dittybopper :)')
                    }
          }
      }
    }
    stage('Install Loki Operator') {
            agent { label params['JENKINS_AGENT_LABEL'] }
            when {
                expression { params.LOKI_OPERATOR != 'None' }
            }
            steps {
                copyArtifacts(
                filter: '',
                fingerprintArtifacts: true,
                projectName: 'ocp-common/Flexy-install',
                selector: specific(params.BUILD_NUMBER),
                target: 'flexy-artifacts'
                )
                script {                  
                    // if an 'Unreleased' installation, use aosqe-index image for unreleased CatalogSource image
                    if (params.LOKI_OPERATOR == 'Unreleased') {
                        env.DOWNSTREAM_IMAGE = "quay.io/openshift-qe-optional-operators/aosqe-index:v${env.MAJOR_VERSION}.${env.MINOR_VERSION}"
                    }
                    // attempt installation of Loki Operator from selected source
                    println("Installing ${params.LOKI_OPERATOR} version of Loki Operator...")
                    lokiReturnCode = sh(returnStatus: true, script: """
                    if [ ! -d ~/.kube ];then
                       mkdir -p ~/.kube
                    fi
                    cp $WORKSPACE/flexy-artifacts/workdir/install-dir/auth/kubeconfig ~/.kube/config
                    
                        source $WORKSPACE/scripts/netobserv.sh
                        deploy_lokistack
                    """)
                    // fail pipeline if installation failed
                    if (lokiReturnCode.toInteger() != 0) {
                        error("${params.LOKI_OPERATOR} version of Loki Operator installation failed :(")
                    }
                    // otherwise continue and display controller and lokistack pods running in cluster
                    else {
                        println("Successfully installed ${params.LOKI_OPERATOR} version of Loki Operator :)")
                        sh(returnStatus: true, script: '''
                            oc get pods -n openshift-operators-redhat
                            oc get pods -n netobserv
                        ''')
                    }
                }
            }
    }
    stage('Install NetObserv Operator') {
            agent { label params['JENKINS_AGENT_LABEL'] }
            when {
                expression { params.INSTALLATION_SOURCE != 'None' }
            }
            steps {
                copyArtifacts(
                filter: '',
                fingerprintArtifacts: true,
                projectName: 'ocp-common/Flexy-install',
                selector: specific(params.BUILD_NUMBER),
                target: 'flexy-artifacts'
                )                
                script {                    
                    // if an 'Internal' installation, determine whether to use aosqe-index image or specific IIB image
                    if (params.INSTALLATION_SOURCE == 'Internal' && params.IIB_OVERRIDE != '') {
                        env.DOWNSTREAM_IMAGE = "brew.registry.redhat.io/rh-osbs/iib:${params.IIB_OVERRIDE}"
                    }
                    else {
                        env.DOWNSTREAM_IMAGE = "quay.io/openshift-qe-optional-operators/aosqe-index:v${env.MAJOR_VERSION}.${env.MINOR_VERSION}"
                    }
                    // if a 'Source' installation, determine whether to use main image or specific premerge image
                    if (params.INSTALLATION_SOURCE == 'Source' && params.OPERATOR_PREMERGE_OVERRIDE != '') {
                        env.UPSTREAM_IMAGE = "quay.io/netobserv/network-observability-operator-catalog:v0.0.0-${OPERATOR_PREMERGE_OVERRIDE}"
                    }
                    else {
                        env.UPSTREAM_IMAGE = "quay.io/netobserv/network-observability-operator-catalog:v0.0.0-main"
                    }
                    // attempt installation of Network Observability from selected source
                    println("Installing Network Observability from ${params.INSTALLATION_SOURCE}...")
                    netobservReturnCode = sh(returnStatus: true, script: """
                    if [ ! -d ~/.kube ];then
                       mkdir -p ~/.kube
                    fi
                    cp $WORKSPACE/flexy-artifacts/workdir/install-dir/auth/kubeconfig ~/.kube/config                    
                        source $WORKSPACE/scripts/netobserv.sh
                        deploy_netobserv
                    """)
                    // fail pipeline if installation failed
                    if (netobservReturnCode.toInteger() != 0) {
                        error("Network Observability installation from ${params.INSTALLATION_SOURCE} failed :(")
                    }
                    // patch in premerge images if specified, fail pipeline if patching fails on any component
                    if (params.EBPF_PREMERGE_OVERRIDE != '') {
                        env.EBPF_PREMERGE_IMAGE = "quay.io/netobserv/netobserv-ebpf-agent:${EBPF_PREMERGE_OVERRIDE}"
                        netobservEBPFPatchReturnCode = sh(returnStatus: true, script: """
                            source $WORKSPACE/scripts/netobserv.sh
                            patch_netobserv "ebpf" $EBPF_PREMERGE_IMAGE
                        """)
                        if (netobservEBPFPatchReturnCode.toInteger() != 0) {
                            error("Network Observability eBPF image patch ${params.EBPF_PREMERGE_OVERRIDE} failed :(")
                        }
                    }
                    if (params.FLP_PREMERGE_OVERRIDE != '') {
                        env.FLP_PREMERGE_IMAGE = "quay.io/netobserv/flowlogs-pipeline:${FLP_PREMERGE_OVERRIDE}"
                        netobservFLPPatchReturnCode = sh(returnStatus: true, script: """
                            source $WORKSPACE/scripts/netobserv.sh
                            patch_netobserv "flp" $FLP_PREMERGE_IMAGE
                        """)
                        if (netobservFLPPatchReturnCode.toInteger() != 0) {
                            error("Network Observability FLP image patch ${params.FLP_PREMERGE_OVERRIDE} failed :(")
                        }
                    }
                    if (params.PLUGIN_PREMERGE_OVERRIDE != '') {
                        env.PLUGIN_PREMERGE_IMAGE = "quay.io/netobserv/network-observability-console-plugin:${PLUGIN_PREMERGE_OVERRIDE}"
                        netobservPluginPatchReturnCode = sh(returnStatus: true, script: """
                            source $WORKSPACE/scripts/netobserv.sh
                            patch_netobserv "plugin" $PLUGIN_PREMERGE_IMAGE
                        """)
                        if (netobservPluginPatchReturnCode.toInteger() != 0) {
                            error("Network Observability Plugin image patch ${params.PLUGIN_PREMERGE_OVERRIDE} failed :(")
                        }
                    }
                    // if installation and patching succeeds, continue and display controller, FLP, and eBPF pods running in cluster
                    else {
                        println("Successfully installed Network Observability from ${params.INSTALLATION_SOURCE} :)")
                        sh(returnStatus: true, script: '''
                            oc get pods -n openshift-netobserv-operator
                            oc get pods -n netobserv
                            oc get pods -n netobserv-privileged
                        ''')
                    }
                }
            }
    }
    stage('Configure NetObserv, flowcollector, and Kafka') {
            agent { label params['JENKINS_AGENT_LABEL'] }
            steps {
                copyArtifacts(
                filter: '',
                fingerprintArtifacts: true,
                projectName: 'ocp-common/Flexy-install',
                selector: specific(params.BUILD_NUMBER),
                target: 'flexy-artifacts'
                )                
                script {                    
                    // capture NetObserv release and add it to build description
                    env.RELEASE = sh(returnStdout: true, script: "oc get pods -l app=netobserv-operator -o jsonpath='{.items[*].spec.containers[1].env[0].value}' -A").trim()
                    if (env.RELEASE != '') {
                        currentBuild.description += "NetObserv Release: <b>${env.RELEASE}</b><br/>"
                    }
                    // attempt updating common parameters of NetObserv and flowcollector where specified
                    println('Updating common parameters of NetObserv and flowcollector where specified...')
                    if (params.CONTROLLER_MEMORY_LIMIT != '') {
                        controllerReturnCode = sh(returnStatus: true, script: """
                            oc -n openshift-netobserv-operator patch csv $RELEASE --type=json -p "[{"op": "replace", "path": "/spec/install/spec/deployments/0/spec/template/spec/containers/0/resources/limits/memory", "value": ${params.CONTROLLER_MEMORY_LIMIT}}]"
                            sleep 60
                        """)
                        if (controllerReturnCode.toInteger() != 0) {
                            error('Updating controller memory limit failed :(')
                        }
                    }
                    if (params.EBPF_SAMPLING_RATE != '') {
                        samplingReturnCode = sh(returnStatus: true, script: """
                            oc patch flowcollector cluster --type=json -p "[{"op": "replace", "path": "/spec/agent/ebpf/sampling", "value": ${params.EBPF_SAMPLING_RATE}}] -n netobserv"
                        """)
                        if (samplingReturnCode.toInteger() != 0) {
                            error('Updating eBPF sampling rate failed :(')
                        }
                    }
                    if (params.EBPF_MEMORY_LIMIT != '') {
                        ebpfMemReturnCode = sh(returnStatus: true, script: """
                            oc patch flowcollector cluster --type=json -p "[{"op": "replace", "path": "/spec/agent/ebpf/resources/limits/memory", "value": "${params.EBPF_MEMORY_LIMIT}"}] -n netobserv"
                        """)
                        if (ebpfMemReturnCode.toInteger() != 0) {
                            error('Updating eBPF memory limit failed :(')
                        }
                    }
                    if (params.FLP_CPU_LIMIT != '') {
                        flpCpuReturnCode = sh(returnStatus: true, script: """
                            oc patch flowcollector cluster --type=json -p "[{"op": "replace", "path": "/spec/processor/resources/limits/cpu", "value": "${params.FLP_CPU_LIMIT}"}] -n netobserv"
                        """)
                        if (flpCpuReturnCode.toInteger() != 0) {
                            error('Updating FLP CPU limit failed :(')
                        }
                    }
                    if (params.FLP_MEMORY_LIMIT != '') {
                        flpMemReturnCode = sh(returnStatus: true, script: """
                            oc patch flowcollector cluster --type=json -p "[{"op": "replace", "path": "/spec/processor/resources/limits/memory", "value": "${params.FLP_MEMORY_LIMIT}"}] -n netobserv"
                        """)
                        if (flpMemReturnCode.toInteger() != 0) {
                            error('Updating FLP memory limit failed :(')
                        }
                    }
                    println('Successfully updated common parameters of NetObserv and flowcollector :)')
                    // attempt to enable or update Kafka if applicable
                    println('Checking if Kafka needs to be enabled or updated...')
                    if (params.ENABLE_KAFKA == true) {
                        println("Deploy Kafka in Openshift...")
                        kafkaReturnCode = sh(returnStatus: true, script: """
                            source $WORKSPACE/scripts/netobserv.sh
                            deploy_kafka
                            deploy-xk6-kafka
                        """)

                        if (params.ENABLE_FLOWCOLLECTOR_KAFKA == true) {
                        println("Configuring Kafka in flowcollector...")
                        kafkaFlowControlReturnCode = sh(returnStatus: true, script: """
                            source $WORKSPACE/scripts/netobserv.sh
                            update_flowcollector_use_kafka_deploymentModel
                        """)
                        if (kafkaFlowControlReturnCode.toInteger() != 0){
                               error('Failed to update flowcollector use kafka deploymentModel :(')
                        }

                        }
                        // fail pipeline if installation and/or configuration failed
                        if (kafkaReturnCode.toInteger() != 0 ) {
                            error('Failed to enable Kafka in flowcollector :(')
                        }
                        // otherwise continue and display controller and updated FLP pods running in cluster
                        else {
                            println('Successfully enabled Kafka with flowcollector :)')
                            sh(returnStatus: true, script: '''
                                oc get pods -n openshift-operators
                                oc get pods -n netobserv
                            ''')
                        }
                    }
                    else {
                        println('Skipping Kafka configuration...')
                    }
                }
            }
        }
    stage('Run Workload') {
            agent { label params['JENKINS_AGENT_LABEL'] }
            when {
                expression { params.WORKLOAD != 'None' }
            }
            steps {
                copyArtifacts(
                filter: '',
                fingerprintArtifacts: true,
                projectName: 'ocp-common/Flexy-install',
                selector: specific(params.BUILD_NUMBER),
                target: 'flexy-artifacts'
                )                
                script {
                    // set build name and remove previous artifacts
                    currentBuild.displayName = "${currentBuild.displayName}-${params.WORKLOAD}"
                    sh(script: "rm -rf $WORKSPACE/workload-artifacts/*.json")
                    // build workload job based off selected workload
                    if (params.WORKLOAD == 'router-perf') {
                        env.JENKINS_JOB = 'scale-ci/e2e-benchmarking-multibranch-pipeline/router-perf'
                        workloadJob = build job: env.JENKINS_JOB, parameters: [
                            string(name: 'BUILD_NUMBER', value: params.FLEXY_BUILD_NUMBER),
                            booleanParam(name: 'CERBERUS_CHECK', value: params.CERBERUS_CHECK),
                            booleanParam(name: 'MUST_GATHER', value: true),
                            string(name: 'IMAGE', value: NETOBSERV_MUST_GATHER_IMAGE),
                            string(name: 'JENKINS_AGENT_LABEL', value: params.JENKINS_AGENT_LABEL),
                            booleanParam(name: 'GEN_CSV', value: false),
                            string(name: 'LARGE_SCALE_CLIENTS', value: params.LARGE_SCALE_CLIENTS),
                            string(name: 'LARGE_SCALE_CLIENTS_MIX', value: params.LARGE_SCALE_CLIENTS_MIX),
                            string(name: 'E2E_BENCHMARKING_REPO', value: params.E2E_BENCHMARKING_REPO),
                            string(name: 'E2E_BENCHMARKING_REPO_BRANCH', value: params.E2E_BENCHMARKING_REPO_BRANCH)
                        ]
                    }
                    else if (params.WORKLOAD == 'ingress-perf') {
                        env.JENKINS_JOB = 'scale-ci/e2e-benchmarking-multibranch-pipeline/ingress-perf'
                        workloadJob = build job: env.JENKINS_JOB, parameters: [
                            string(name: 'BUILD_NUMBER', value: params.FLEXY_BUILD_NUMBER),
                            booleanParam(name: 'CERBERUS_CHECK', value: params.CERBERUS_CHECK),
                            booleanParam(name: 'MUST_GATHER', value: true),
                            string(name: 'IMAGE', value: NETOBSERV_MUST_GATHER_IMAGE),
                            string(name: 'JENKINS_AGENT_LABEL', value: params.JENKINS_AGENT_LABEL),
                            booleanParam(name: 'GEN_CSV', value: false),
                            string(name: 'E2E_BENCHMARKING_REPO', value: params.E2E_BENCHMARKING_REPO),
                            string(name: 'E2E_BENCHMARKING_REPO_BRANCH', value: params.E2E_BENCHMARKING_REPO_BRANCH)
                        ]
                    }
                    else {
                        env.JENKINS_JOB = 'scale-ci/e2e-benchmarking-multibranch-pipeline/kube-burner-ocp'
                        workloadJob = build job: env.JENKINS_JOB, parameters: [
                            string(name: 'BUILD_NUMBER', value: params.FLEXY_BUILD_NUMBER),
                            string(name: 'WORKLOAD', value: params.WORKLOAD),
                            booleanParam(name: 'CLEANUP', value: true),
                            booleanParam(name: 'CERBERUS_CHECK', value: params.CERBERUS_CHECK),
                            booleanParam(name: 'MUST_GATHER', value: true),
                            string(name: 'IMAGE', value: NETOBSERV_MUST_GATHER_IMAGE),
                            string(name: 'VARIABLE', value: params.VARIABLE), 
                            string(name: 'NODE_COUNT', value: params.NODE_COUNT),
                            booleanParam(name: 'GEN_CSV', value: false),
                            string(name: 'JENKINS_AGENT_LABEL', value: params.JENKINS_AGENT_LABEL),
                            string(name: 'E2E_BENCHMARKING_REPO', value: params.E2E_BENCHMARKING_REPO),
                            string(name: 'E2E_BENCHMARKING_REPO_BRANCH', value: params.E2E_BENCHMARKING_REPO_BRANCH)
                        ]
                    }
                    // fail pipeline if workload failed
                    if (workloadJob.result != 'SUCCESS') {
                        error('Workload job failed :(')
                    }
                    // otherwise continue and update build description with workload job link
                    else {
                        println("Successfully ran workload job :)")
                        env.JENKINS_BUILD = "${workloadJob.getNumber()}"
                        currentBuild.description += "Workload Job: <b><a href=${workloadJob.absoluteUrl}>${env.JENKINS_BUILD}</a></b> (workload <b>${params.WORKLOAD}</b> was run)<br/>"
                    }
                }
                // copy artifacts from workload job
                copyArtifacts(
                    fingerprintArtifacts: true, 
                    projectName: env.JENKINS_JOB,
                    selector: specific(env.JENKINS_BUILD),
                    target: 'workload-artifacts',
                    flatten: true
                )
                script {
                    // set new env vars from workload 'index_data' JSON file and update build description fields
                    workloadInfo = readJSON(file: "$WORKSPACE/workload-artifacts/index_data.json")
                    workloadInfo.each { env.setProperty(it.key.toUpperCase(), it.value) }
                    // UUID
                    currentBuild.description += "<b>UUID:</b> ${env.UUID}<br/>"
                    // STARTDATE is string rep of start time
                    currentBuild.description += "<b>STARTDATE:</b> ${env.STARTDATE}<br/>"
                    // ENDDATE is string rep of end time
                    currentBuild.description += "<b>ENDDATE:</b> ${env.ENDDATE}<br/>"
                    // STARTDATEUNIXTIMESTAMP is unix timestamp of start time
                    currentBuild.description += "<b>STARTDATEUNIXTIMESTAMP:</b> ${env.STARTDATEUNIXTIMESTAMP}<br/>"
                    // ENDDATEUNIXTIMESTAMP is unix timestamp of end time
                    currentBuild.description += "<b>ENDDATEUNIXTIMESTAMP:</b> ${env.ENDDATEUNIXTIMESTAMP}<br/>"
                }
            }
    }
    stage("Create google sheet") {
        agent { label params['JENKINS_AGENT_LABEL'] }
        when { 
            expression { params.GEN_CSV == true }
        }
        steps {
            script {
                
                compare_job = build job: 'scale-ci/e2e-benchmarking-multibranch-pipeline/benchmark-comparison',
                    parameters: [
                        string(name: 'BUILD_NUMBER', value: BUILD_NUMBER),text(name: "ENV_VARS", value: ENV_VARS),
                        string(name: 'JENKINS_AGENT_LABEL', value: JENKINS_AGENT_LABEL),booleanParam(name: "GEN_CSV", value: GEN_CSV),
                        string(name: "WORKLOAD", value: WORKLOAD), string(name: "UUID", value: env.UUID),
                        string(name: "COMPARISON_CONFIG_PARAM", value: COMPARISON_CONFIG),
                        string(name: "TOLERANCY_RULES_PARAM", value: ""), string(name: "EMAIL_ID_OVERRIDE", value: EMAIL_ID_OVERRIDE)
                    ],
                    propagate: false
            }
        }
    }
    stage("Compare results with baseline uuid and print to google sheet") {
        agent { label params['JENKINS_AGENT_LABEL'] }
        when { 
            expression { params.GEN_CSV == true }
        }
        steps {
            script {
                
                compare_job = build job: 'scale-ci/e2e-benchmarking-multibranch-pipeline/benchmark-comparison',
                    parameters: [
                        string(name: 'BUILD_NUMBER', value: BUILD_NUMBER),text(name: "ENV_VARS", value: ENV_VARS),
                        string(name: 'JENKINS_AGENT_LABEL', value: JENKINS_AGENT_LABEL),booleanParam(name: "GEN_CSV", value: GEN_CSV),
                        string(name: "WORKLOAD", value: WORKLOAD), string(name: "UUID", value: env.UUID),
                        string(name: "COMPARISON_CONFIG_PARAM", value: COMPARISON_CONFIG),string(name: "TOLERANCY_RULES_PARAM", value: TOLERANCY_RULES),
                        string(name: "EMAIL_ID_OVERRIDE", value: EMAIL_ID_OVERRIDE)
                    ],
                    propagate: false
            }
        }
    }
    stage("Check cluster health") {
        agent { label params['JENKINS_AGENT_LABEL'] }
        when {
            expression { params.CERBERUS_CHECK == true }
        }
        steps {
            script {
                cerberus_job = build job: 'scale-ci/e2e-benchmarking-multibranch-pipeline/cerberus',
                    parameters: [
                        string(name: 'BUILD_NUMBER', value: BUILD_NUMBER),text(name: "ENV_VARS", value: ENV_VARS),
                        string(name: "CERBERUS_ITERATIONS", value: "1"), string(name: "CERBERUS_WATCH_NAMESPACES", value: "[^.*\$]"),
                        string(name: 'CERBERUS_IGNORE_PODS', value: "[^installer*, ^kube-burner*, ^redhat-operators*, ^certified-operators*]"),
                        string(name: 'JENKINS_AGENT_LABEL', value: JENKINS_AGENT_LABEL),booleanParam(name: "INSPECT_COMPONENTS", value: true),
                        string(name: "WORKLOAD", value: WORKLOAD),booleanParam(name: "MUST_GATHER", value: MUST_GATHER),
                        string(name: 'IMAGE', value: IMAGE),string(name: 'IMAGE_STREAM', value: IMAGE_STREAM)
                    ],
                    propagate: false
                if (status == "PASS") {
                    if (cerberus_job.result.toString() != "SUCCESS") {
                        status = "Cerberus check failed"
                        currentBuild.result = "FAILURE"
                    }
                }
                else {
                    if (cerberus_job.result.toString() != "SUCCESS") {
                        status += "Cerberus check failed"
                        currentBuild.result = "FAILURE"
                    }
                }
            }
        }
    }
    stage("Write out results") {
      agent { label params['JENKINS_AGENT_LABEL'] }
      when {
          expression { params.WRITE_TO_FILE == true }
      }
        steps {
          script {
              if (status != "PASS") {
                  currentBuild.result = "FAILURE"
              }
              def parameter_to_pass = VARIABLE
              build job: 'scale-ci/e2e-benchmarking-multibranch-pipeline/write-scale-ci-results',
                  parameters: [
                      string(name: 'BUILD_NUMBER', value: BUILD_NUMBER),text(name: "ENV_VARS", value: ENV_VARS),
                      string(name: 'CI_JOB_ID', value: BUILD_ID), string(name: 'CI_JOB_URL', value: BUILD_URL),
                      string(name: 'JENKINS_AGENT_LABEL', value: JENKINS_AGENT_LABEL), string(name: "CI_STATUS", value: "${status}"),
                      string(name: "JOB", value: WORKLOAD), string(name: "JOB_PARAMETERS", value: "${parameter_to_pass}" ),
                      string(name: "JENKINS_JOB_NUMBER", value: JENKINS_JOB_NUMBER), string(name: "JENKINS_JOB_PATH", value: JOB_NAME)
                  ],
                  propagate: false
            }
        }
    }
    stage("Write es results") {
      agent { label params['JENKINS_AGENT_LABEL'] }
      when {
          expression { params.WRITE_TO_ES == true }
      }
        steps {
          script {
                build job: 'scale-ci/e2e-benchmarking-multibranch-pipeline/post-results-to-es',
                  parameters: [
                      string(name: 'BUILD_NUMBER', value: BUILD_NUMBER),text(name: "ENV_VARS", value: ENV_VARS),
                      string(name: "JENKINS_JOB_NUMBER", value: JENKINS_JOB_NUMBER), string(name: "JENKINS_JOB_PATH", value: JOB_NAME),
                      string(name: 'JENKINS_AGENT_LABEL', value: JENKINS_AGENT_LABEL), string(name: "CI_STATUS", value: "${status}"),
                      string(name: "WORKLOAD", value: WORKLOAD)
                  ],
                  propagate: false
            }
        }
    }
    stage("Scale down workers") {
      agent { label params['JENKINS_AGENT_LABEL'] }
      when {
          expression { params.SCALE_DOWN.toInteger() > 0 }
      }
      steps {
          script {
              build job: 'scale-ci/e2e-benchmarking-multibranch-pipeline/cluster-workers-scaling',
                  parameters: [
                      string(name: 'BUILD_NUMBER', value: BUILD_NUMBER), string(name: 'WORKER_COUNT', value: SCALE_DOWN),
                      text(name: "ENV_VARS", value: ENV_VARS), string(name: 'JENKINS_AGENT_LABEL', value: JENKINS_AGENT_LABEL),
                      booleanParam(name: 'INSTALL_DITTYBOPPER', value: false)
                  ]
          }
      }
    }
  }
    post {
        always {
            script {
                if (params.SEND_SLACK == true ) {
                        build job: 'scale-ci/e2e-benchmarking-multibranch-pipeline/post-to-slack',
                        parameters: [
                            string(name: 'BUILD_NUMBER', value: BUILD_NUMBER), string(name: 'WORKLOAD', value: WORKLOAD),
                            text(name: "BUILD_URL", value: env.BUILD_URL), string(name: 'BUILD_ID', value: currentBuild.number.toString()),string(name: 'RESULT', value:currentBuild.currentResult)
                        ], propagate: false
                }
            }
        }
    }  
}
