# ocp-dr

# OpenShift Disaster Recovery Automation

This repository contains the automation scripts and configuration files for a robust, on-demand Disaster Recovery (DR) procedure for an OpenShift 4.17 cluster.

## DR Runbook: OpenShift Cluster Infrastructure Recovery

| | |
|---|---|
| **Document Version:** | 2.0 |
| **Last Updated:** | June 26, 2025 |
| **Owner:** | OpenShift Platform Team |
| **Scope:** | Recovery of the OpenShift Cluster **infrastructure layer** in the DR site. |
| **Author:** | [Fabrizio Verde](faverde@redhat.com) |

---

### 1. Introduction and Scope

This document provides the step-by-step procedure for recreating the OpenShift cluster infrastructure in a designated DR site. The procedure utilizes a "cold site" approach, where the cluster and its nodes are provisioned on-demand using automation scripts.

The recovery is divided into distinct, sequential phases, from base cluster creation to node provisioning and finally to configuration via GitOps with Red Hat Advanced Cluster Management (ACM).

#### 1.1. In Scope
* Validating the DR environment prerequisites.
* Creating a new OpenShift 4.17 cluster (master nodes only).
* **Provisioning worker, infra, and infra-odf node pools using MachineSets.**
* Applying standard configurations (taints, labels) to the new nodes.
* Bootstrapping the cluster with ACM and connecting it to this Git repository.
* Handing off control to ACM to complete the installation of all other infrastructure operators (LSO, ODF, etc.) via GitOps policies.
* Validating the health of the recovered cluster infrastructure.

#### 1.2. Out of Scope
* **Recovery of the DR vSphere environment.**
* **Restoration of core VMs** (Bastion, Git Server, Quay Registry). This is handled by the **Systems Team**.
* **Configuration of DR networking and DNS.** This is handled by the **Network Team**.
* **Recovery of applications.** This is handled by the **Application Team** via OpenShift GitOps after the infrastructure is declared ready.

---

### 2. Recovery Procedure

Execute these phases sequentially from the restored Bastion Host.

### Important Note on Secrets and Untracked Files

> **WARNING: Critical File Backup Required**
>
> This repository includes a `.gitignore` file to prevent sensitive data and large state directories from being accidentally committed to the Git history. Please be aware that the following critical files are **intentionally not tracked by Git**:
>
> * `ocp_configs/dr.vars`
> * `ocp_configs/install-config.yaml`
> * `ocp_configs/pull-secret.json`
> * `ocp_configs/github-pat`
> * `dr-bootstrap/acm/03_channel.yaml`
> * `install-dir/`
> * `install-dir-bck/`
>
> **ACTION REQUIRED:** Because these files are not tracked by the repository, they will not be restored by a `git clone` or `git pull`. It is your responsibility to **securely back up these files and directories elsewhere**. They contain sensitive credentials and state information that are essential for successfully executing or re-running the disaster recovery procedure.

#### **Phase 1: Preparation and Prerequisites**

Before starting, ensure **every single one** of the following conditions is met:

-   [ ] A disaster has been formally declared and the decision to failover has been made.
-   [ ] **Confirmation Received:** The **Systems Team** has confirmed that the Bastion, Git, and Quay VMs have been successfully restored, powered on, and have network connectivity.
-   [ ] **Confirmation Received:** The **Network Team** has confirmed that all required DR networking, firewall rules, and DNS are active.
-   [ ] **Access:** You have SSH access to the restored Bastion Host.
-   [ ] **Git Repository:** This Git repository has been cloned to the Bastion Host.
-   [ ] **Configuration (`dr.vars`):** The `ocp_configs/dr.vars` file has been created from its template and populated with all correct values for the DR environment.

    **Note on Configuration:** The Git repository contains a template at `ocp_configs/dr.vars.template` with placeholder values. To prepare for the DR procedure, you must first create your local configuration by copying this file:
    ```bash
    cp ocp_configs/dr.vars.template ocp_configs/dr.vars
    ```
    Next, edit the newly created `ocp_configs/dr.vars` file and replace all placeholders with the real values for your environment (vCenter credentials, node counts, etc.). The `dr.vars` file is intentionally listed in `.gitignore` and **must not be committed to the repository** to protect sensitive data.


#### **Phase 2: Base Cluster Provisioning**

This phase creates the minimal OpenShift cluster (master nodes only).

1.  **Navigate to the scripts directory:**
    ```bash
    cd /path/to/your/cloned/repo
    ```
    ```bash
    cd scripts
    ```
2.  **Run the Prerequisite Check Script:**
    ```bash
    ./00_prerequisites-check.sh
    ```
    *This script validates connectivity, DNS, and tools on the bastion.*

3.  **Generate the `install-config.yaml`:**
    ```bash
    ./01_generate-install-config.sh
    ```
    *This script creates the configuration file and a pre-installation backup.*

4.  **Create the OpenShift Cluster (Masters Only):**
    ```bash
    ./02_create-cluster.sh
    ```
    *This is the main installation step and will take a considerable amount of time.*

#### **Phase 3: Worker and Infra Node Provisioning**

With the control plane active, this phase provisions the required node pools.

1.  **Create All Node Pools:**
    ```bash
    ./03_create-nodes.sh
    ```
    * **What it does:** This script reads variables from `dr.vars` to:
        * Create three `MachineSet` objects: `worker`, `infra`, and `infra-odf`.
        * The `infra-odf` nodes are automatically labeled (`cluster.ocs.openshift.io/openshift-storage`) to be ready for ODF.
        * A `MachineConfig` is applied to taint all `infra` nodes, ensuring only designated workloads can run on them.
    * **Wait for completion:** The script will wait until all requested nodes have been provisioned by vSphere and have joined the cluster in a `Ready` state. This can take a long time.

#### **Phase 4: ACM Bootstrap and GitOps Configuration**

Now that the cluster has its nodes, we can bootstrap ACM and hand over control.

1.  **Create Git Channel, Bootstrap ACM and Connect to Git:**
    ```bash
    ./create-channel.sh
    ```
    ```bash
    ./05_bootstrap-acm.sh
    ```
    * **What it does:** This script installs the ACM operator, creates the `MultiClusterHub`, and applies the initial `Application` resource. This `Application` points ACM to the `hub-cluster-config/` directory in this Git repository, activating the GitOps workflow.
2.  **Monitor GitOps Synchronization:** From this point on, ACM is in control. Monitor its progress from the OpenShift console in the "Applications" and "Governance" sections. ACM will now read your Kustomize overlays and begin deploying the policies for LSO, ODF, and other operators.

#### **Phase 5: Validation and Handoff**

1.  **Run the Final Validation Script:** Once ACM reports that all applications and policies are compliant, run the validation script to confirm the overall health.
    ```bash
    ./06_validate-dr-cluster.sh
    ```
2.  **Handoff to Application Team:** Formally notify the application team that the infrastructure is ready for them to begin their own application recovery procedures.

---

## 4. Appendix

### Appendix A: Placeholder Variables

This section lists all variables defined in the `ocp_configs/dr.vars` file. Ensure all these are correctly populated before starting the procedure.

| Variable Name | Description |
|---|---|
| **Cluster Details** | |
| `OCP_CLUSTER_NAME` | The name of the OpenShift cluster. |
| `OCP_BASE_DOMAIN` | The base domain for the cluster (e.g., example.com). |
| `OCP_PULL_SECRET_PATH` | Absolute path to the file containing your Red Hat pull secret JSON. |
| `OCP_SSH_KEY_PATH` | Absolute path to the public SSH key file for node access. |
| `OCP_INSTALL_DIR` | A local directory on the bastion to store installation artifacts. |
| **Sizing Details** | |
| `OCP_MASTER_CPU` | Number of vCPUs for each master node. |
| `OCP_CORES_PER_SOCKET` | Number of cores per socket for master nodes. |
| `OCP_MASTER_MEMORY`| Memory in MB for each master node (e.g., 32768 for 32GB). |
| `OCP_DISK_SIZE_GB` | Size of the OS disk in GB for master nodes. |
| **Networking Details**| |
| `OCP_API_VIP` | The static virtual IP for the cluster's API endpoint. Must be free. |
| `OCP_INGRESS_VIP` | The static virtual IP for user-facing application traffic. Must be free. |
| `OCP_CLUSTER_NETWORK_CIDR`| The IP address block for Pods (internal to the cluster). |
| `OCP_MACHINE_NETWORK_CIDR`| The IP address block where the cluster nodes (VMs) will be created. |
| `OCP_SERVICE_NETWORK_CIDR`| The IP address block for Services (internal to the cluster). |
| **vSphere Details** | |
| `VSPHERE_SERVER` | FQDN or IP address of the DR vCenter Server. |
| `VSPHERE_CERT_PATH` | **(New)** Absolute path to the vCenter CA certificate file (.pem format). |
| `VSPHERE_USER` | The username for connecting to vCenter. |
| `VSPHERE_PASSWORD` | The password for the vCenter user. |
| `VSPHERE_DATACENTER` | The name of the Datacenter object in the DR vCenter. |
| `VSPHERE_CLUSTER` | The name of the Cluster object where nodes will be deployed. |
| `VSPHERE_DATASTORE`| The name of the Datastore to use for VMs. |
| `VSPHERE_NETWORK` | The name of the vSphere network (Port Group) for the VMs. |
| `VSPHERE_FOLDER` | Full path to the VM Folder for organizing cluster VMs. |
| `VSPHERE_RESOURCEPOOL`| Full path to the Resource Pool for the cluster. |
| **External Services** | |
| `BASTION_HOST` | FQDN of the DR bastion host (for reference). |
| `GIT_SERVER` | FQDN of the internal Git server. |
| `QUAY_SERVER` | FQDN of the internal Quay registry. |
| **Node Sizing & Replicas** | |
| `OCP_VSPHERE_VM_TEMPLATE` | Name of the vSphere VM template for creating nodes (e.g., `cluster-id-rhcos`). |
| `OCP_WORKER_NODE_REPLICAS` | Number of worker nodes to create. |
| `OCP_WORKER_NODE_CPU` | Number of vCPUs for each worker node. |
| `OCP_WORKER_NODE_MEMORY` | Memory in MB for each worker node. |
| `OCP_WORKER_NODE_DISK_GB` | Disk size in GB for each worker node. |
| `OCP_INFRA_NODE_REPLICAS` | Number of infra nodes to create. |
| `OCP_INFRA_NODE_CPU` | Number of vCPUs for each infra node. |
| `OCP_INFRA_NODE_MEMORY` | Memory in MB for each infra node. |
| `OCP_INFRA_NODE_DISK_GB` | Disk size in GB for each infra node. |
| `OCP_INFRA_ODF_NODE_REPLICAS` | Number of ODF-dedicated nodes to create. |
| `OCP_INFRA_ODF_NODE_CPU` | Number of vCPUs for each ODF node. |
| `OCP_INFRA_ODF_NODE_MEMORY` | Memory in MB for each ODF node. |
| `OCP_INFRA_ODF_NODE_DISK_GB` | Disk size in GB for each ODF node. |


### Appendix B: Troubleshooting

* **Installation Fails:** Check the log file `${OCP_INSTALL_DIR}/.openshift_install.log` for detailed error messages. Common issues are related to vCenter credentials, network connectivity (check firewalls and routing), or unavailable VIPs.
* **Operator Fails to Install:** Use `oc get pods -n <namespace>` and `oc describe pod <pod-name> -n <namespace>` to investigate issues with specific operator pods. Check the operator's subscription status with `oc get csv -n <namespace>`.
* **Connectivity Issues:** Use the `scripts/00_prerequisites-check.sh` script to re-validate connectivity to core services at any time.
* **CRD Not Found:** If a script fails waiting for a CRD, it often means the operator that provides it failed to install correctly. Check the operator's namespace for failing pods.