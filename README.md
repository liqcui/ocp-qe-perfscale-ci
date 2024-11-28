# ocp-qe-perfscale-ci

## Purpose
This repo contains various `Jenkinsfile` and other pertaining content that are used by a multi-branch pipeline in the OCP QE Jenkins instance.

## Structure
There are multiple orphan branches present in this repos, each of them are supposed to house one kind of workload for [E2E-benchmarking](https://github.com/cloud-bulldozer/e2e-benchmarking/). Each branch should contain one `Jenkinsfile`

You can create a new orphan branch simply by `git checkout --orphan BRANCHNAME` for new workload.

The OCP QE Jenkins multi-branch pipeline job will look at the `Jenkinsfile` on each of these branches and create a new workload job for you to execute in your Jenkins.

This repository also hosting the `perf-dashboard-grafana-crs` directory, that includes all the Custom Resources and relevant files that you need to deploy a fully functional perf-scale dashboard. This deployment uses grafana operator to enable grafana operator on your cluster, create an instance, create required datasources(in this case Prometheus and ElasticSearch) and dashboards.

See `launch-grafana.sh` for env variables that are needed. `cleanup-grafana.sh` can be used to clean up everything created by the `launch-grafana.sh` script.

**PREREQUISITE:** is to have `KUBECONFIG` env variable configured that can access your OpenShift cluster. 

## Jobs
This is an overview - for additional details about each job, see the respective `README` in the specific branch for that job. Note that some jobs may call others.

| Job | Purpose |
| --- | --- |
| benchmark-cleaner | TODO |
| benchmark-comparison | TODO |
| cerberus | TODO |
| chaos-upgrade | TODO |
| cluster-builder | TODO |
| cluster-post-config | TODO |
| cluster-workers-scaling | TODO |
| etcd-perf | TODO |
| kraken | TODO |
| kube-burner | TODO |
| kube-burner-ocp | TODO |
| loaded-upgrade | TODO |
| must-gather | TODO |
| netobserv-perf-tests | Used for Performance and Scale testing of the Network Observability Operator |
| network-perf | TODO |
| network-perf-v2 | TODO |
| post-results-to-es | TODO |
| post-to-slack | TODO |
| regression-test | TODO |
| router-perf | TODO |
| upgrade | TODO |
| write-scale-ci-results | TODO |

## Scripts

### Mr. Sandman
Sometimes, the only way to get data such as UUID and workload timestamp information is directly from the workload job runs. If you find yourself in need of this but don't want to manually pour through logs, you can let Mr. Sandman give it a shot by running `./scripts/sandman.py --file <path/to/out/file>`

By default he will output a JSON of data to `./data/workload.json` but you can also output a Shell file for use in BASH environment using the `--output sh` flag

## Authors
Kedar Kulkarni <@kedark3 on Github>

Paige Rubendall <@paigerube14 on Github>

Nathan Weinberg <@nathan-weinberg on GitHub>
