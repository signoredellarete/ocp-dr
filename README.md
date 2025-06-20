# ocp-dr

# DR Runbook: OpenShift Cluster Infrastructure Recovery

| | |
|---|---|
| **Document Version:** | 1.0 |
| **Last Updated:** | June 19, 2025 |
| **Owner:** | OpenShift Platform Team |
| **Scope:** | Recovery of the OpenShift Cluster **infrastructure layer** in the DR site. |

---

## 1. Introduction and Scope

This document provides the step-by-step procedure for recreating the OpenShift cluster infrastructure in the designated Disaster Recovery (DR) site. The procedure relies on pre-configured automation scripts and a "cold site" approach, where the cluster is created on-demand.

### 1.1. In Scope
* Validating the DR environment prerequisites.
* Creating a new OpenShift 4.17 cluster using `openshift-install`.
* Bootstrapping the cluster with core infrastructure operators: Local Storage Operator (LSO), Advanced Cluster Management (ACM).
* Handing off control to ACM to complete the installation of other infrastructure operators (ODF, GitOps, SSO).
* Validating the health of the recovered cluster infrastructure.

### 1.2. Out of Scope
* **Recovery of the DR vSphere environment.**
* **Restoration of core VMs** (Bastion, Git Server, Quay Registry) via Kasten. This is handled by the **Systems Team**.
* **Configuration of DR networking and DNS.** This is handled by the **Network Team**.
* **Recovery of applications.** This is handled by the **Application Team** via OpenShift GitOps after the infrastructure is declared ready.

---

## 2. Prerequisites Checklist

Before starting this procedure, ensure **every single one** of the following conditions is met:

- [ ] A disaster has been formally declared, and the decision to failover has been made.
- [ ] **Confirmation Received:** The **Systems Team** has confirmed that the Bastion, Git, and Quay VMs have been successfully restored by Kasten, powered on, and have network connectivity.
- [ ] **Confirmation Received:** The **Network Team** has confirmed that all required DR networking, firewall rules, and DNS configurations are active and in place.
- [ ] **Access:** You have SSH access to the restored Bastion Host (`dr-bastion.example.com`).
- [ ] **Permissions:** The user on the Bastion Host has **`sudo` privileges** to manage system-wide certificate trust stores.
- [ ] **Git Repository:** The infrastructure Git repository has been cloned to the Bastion Host (e.g., in `/home/kni/infra-repo`).
- [ ] **Configuration:** All variables in the `ocp_configs/dr.vars` file have been reviewed and populated, including the new `VSPHERE_CERT_PATH`.

**DO NOT PROCEED UNLESS ALL PREREQUISITES ARE MET.**

---

## 3. Recovery Procedure

Execute these steps sequentially from the Bastion Host's command line.

### **Phase 1: DR Procedure Activation**

1.  **SSH into the Bastion Host:**
    ```bash
    ssh your-user@${BASTION_HOST}
    ```
2.  **Navigate to the scripts directory** within your cloned Git repository:
    ```bash
    cd /path/to/your/cloned/repo/scripts
    ```

### **Phase 2: OpenShift Cluster Provisioning**

1.  **Run the Prerequisite Check Script:** This script validates that the environment is ready for the installation.
    ```bash
    ./00_prerequisites-check.sh
    ```
    **Expected Output:** The script should end with the message: `--- Prerequisites Check Completed Successfully! ---`
    *If it fails, do not proceed. Work with the appropriate teams to resolve the issues reported by the script.*

2.  **Generate the `install-config.yaml`:** This script creates the final installation configuration file.
    ```bash
    ./01_generate-install-config.sh
    ```
    **Expected Output:** The script should end with the message: `Successfully generated /path/to/ocp_install_dir/install-config.yaml.`

3.  **Create the OpenShift Cluster:** This is the main installation step and will take a considerable amount of time (typically 60-90 minutes).
    ```bash
    ./02_create-cluster.sh
    ```
    **Expected Output:** The script will stream the `openshift-install` log. A successful run will end with: `--- Cluster Creation Completed Successfully! ---`

### **Phase 3: Infrastructure Configuration Bootstrap**

1.  **Bootstrap Core Operators:** This script installs LSO and ACM, then lets ACM take over.
    ```bash
    ./03_bootstrap-operators.sh
    ```
    **Expected Output:** The script will complete after initiating the ACM installation, ending with: `--- Operator Bootstrap Script Finished ---`

2.  **Monitor ACM and ODF Installation:** The script finishes quickly, but ACM and ODF take a long time to deploy in the background. Monitor their progress using the following commands:

    * **Set Kubeconfig:**
        ```bash
        source ../ocp_configs/dr.vars
        export KUBECONFIG=${OCP_INSTALL_DIR}/auth/kubeconfig
        ```

    * **Monitor ACM:** Wait for all pods to be `Running` or `Completed`.
        ```bash
        oc get pods -n open-cluster-management -w
        ```

    * **Monitor ODF:** Once ACM is running, it will create the `openshift-storage` namespace and start ODF. Watch for all pods to become `Running` or `Completed`.
        ```bash
        # Wait for the namespace to be created by ACM
        oc get pods -n openshift-storage -w
        ```
    This phase is complete when the `StorageCluster` is `Ready`. Check with: `oc get storagecluster -n openshift-storage`

### **Phase 4: Validation and Handoff**

1.  **Run the Final Validation Script:** Once all operators appear to be running, execute the full validation script to confirm the cluster's health.
    ```bash
    ./04_validate-dr-cluster.sh
    ```
    **Expected Output:** A successful validation will end with the message: `[ SUCCESS ] The OpenShift DR cluster infrastructure appears to be healthy and ready.`

2.  **Handoff to Application Team:** Once validation is successful, formally notify the application team that the infrastructure is ready for them to begin their application recovery procedures.

    **Communication Template:**
    > **Subject:** [DR] OpenShift Infrastructure Ready for Application Recovery
    >
    > **To:** Application Team Leads
    >
    > The OpenShift DR cluster infrastructure has been successfully recovered and validated.
    >
    > **Cluster Console:** `https://console-openshift-console.apps.ocp-cluster.example.com`
    >
    > You may now begin your application recovery procedures using OpenShift GitOps. The platform team is on standby for support.

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


### Appendix B: Troubleshooting

* **Installation Fails:** Check the log file `${OCP_INSTALL_DIR}/.openshift_install.log` for detailed error messages. Common issues are related to vCenter credentials, network connectivity (check firewalls and routing), or unavailable VIPs.
* **Operator Fails to Install:** Use `oc get pods -n <namespace>` and `oc describe pod <pod-name> -n <namespace>` to investigate issues with specific operator pods. Check the operator's subscription status with `oc get csv -n <namespace>`.
* **Connectivity Issues:** Use the `scripts/00_prerequisites-check.sh` script to re-validate connectivity to core services at any time.
* **CRD Not Found:** If a script fails waiting for a CRD, it often means the operator that provides it failed to install correctly. Check the operator's namespace for failing pods.