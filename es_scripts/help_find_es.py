#!/usr/bin/env python3

import os
from . import update_es_uuid


def search_for_entry(METRIC_NAME, info): 
    search_params = {
        "metric_name": METRIC_NAME,
        "jenkins_job_name": info['jenkins_job_name'],
        "jenkins_build_num": info['jenkins_build_num'],
    }

    hits = update_es_uuid.es_search(search_params)
    
    if len(hits) == 0: 
        # return false, no entry was found 
        return False
    else: 
        # returning true that entry was found for the job already
        return True

def edit_uuid_data(workload, uuid_data):

    # if workload == "ingress-perf":
        
    # el
    if workload == "network-perf-v2":

        for k,v in uuid_data: 
            if "metadata." in k: 
                uuid_data[k.replace("metadata.", "")] = uuid_data[k]

        uuid_data['arch'] = uuid_data["clientNodeLabels.kubernetes.io/arch"]
        #print('uuid data' + str(uuid_data))
    #elif workload == "ingress-perf":
        
    # elif workload == "network-perf":
    #     uuid_data['']
    return uuid_data
        

def find_uuid_metadata(workload, current_run_uuid):
    
    search_params = {
        "uuid": current_run_uuid
    }

    if workload == "ingress-perf":
        index="ingress-perf"
    elif workload == "network-perf-v2":
        index="k8s-netperf"
    elif workload == "router-perf":
        index="router-test-results"
    elif workload == "network-perf":
        index="ripsaw-uperf"
    elif workload not in ["upgrade","loaded-upgrade", "nightly-regression"]:
        index="ripsaw-kube-burner"
        search_params["metricName"]= "clusterMetadata"

    
    hits = update_es_uuid.es_search(search_params, index=index)
    #print('hits ' + str(hits))
    uuid_data = hits[0]['_source']
    return edit_uuid_data(uuid_data)

def find_uuid(workload, metric_name, uuid_data):
    current_version = uuid_data['releaseStream'].split(".") 
    #print('find uuid')
    compare_previous = os.getenv("COMPARE_PREVIOUS")
    if str(compare_previous) == "true":
        oc_current_version =  current_version[0] + "."+ str(int(current_version[1]) - 1)
    else:
        oc_current_version = current_version[0] + "."+ current_version[1]


    search_params = {
        "metric_name": metric_name, 
        "workload": workload,
        "network_type": uuid_data['networkType'],
        "worker_count": int(uuid_data['workerNodesCount']),
        "platform": uuid_data['platform'],
        "worker_size": uuid_data['workerNodesType']
    }

    search_wildcard = {
        "ocp_version": str(oc_current_version) + "*"
    }
    hits = update_es_uuid.es_search(search_params, search_wildcard)
    
    if len(hits) == 0: 
        return False
    else: 
        return hits[0]['_source']['uuid']
    
def get_workload_index(workload): 
    if workload == "ingress-perf":
        index="ingress-perf*"
    elif workload == "network-perf-v2":
        index="k8s-netperf"
    elif workload == "router-perf":
        index="router-test-results"
    elif workload == "network-perf":
        index="ripsaw-uperf"
    elif workload not in ["upgrade","loaded-upgrade", "nightly-regression"]:
        index="ripsaw-kube-burner"

    return index

def find_uuid_data(workload, current_run_uuid):
    if workload == "network-perf-v2": 
        workload = "k8s-netperf"
    search_params = {
        "uuid": current_run_uuid,
        "benchmark": workload
    }

    index = "perf_scale_ci*"
    
    hits = update_es_uuid.es_search(search_params, index=index)
    #print('hits ' + str(hits))
    uuid_data = hits[0]['_source']
    return uuid_data

def post_result_data(RESULTS, index = 'perfscale-jenkins-metadata'): 

    for item in RESULTS['data']:
        update_es_uuid.upload_data_to_elasticsearch(item)