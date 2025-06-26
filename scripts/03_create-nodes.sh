#!/bin/bash
set -e

# Load environment variables from config file
source ../ocp_configs/dr.vars

# Set KUBECONFIG to connect to the new cluster
export KUBECONFIG=${OCP_INSTALL_DIR}/auth/kubeconfig

echo "--- Starting Worker and Infra Node Provisioning ---"

# --- Step 1: Gather Dynamically Generated Cluster Information ---
echo "[INFO] Gathering information from the newly created cluster..."

METADATA_FILE="${OCP_INSTALL_DIR}/metadata.json"
if [ ! -f "$METADATA_FILE" ]; then
    echo "[ERROR] Metadata file not found at $METADATA_FILE. Cannot proceed."
    exit 1
fi
export CLUSTER_ID=$(jq -r .infraID ${METADATA_FILE})
echo "[INFO] Found Infrastructure ID (CLUSTER_ID): ${CLUSTER_ID}"

# --- Step 2: Find the default worker MachineSet ---
# This step is now unconditional to ensure the variable is always populated.
echo "[INFO] Finding the default worker MachineSet created by the installer..."
DEFAULT_WORKER_MS_NAME=$(oc get machineset.machine.openshift.io -n openshift-machine-api -l "machine.openshift.io/cluster-api-cluster=${CLUSTER_ID}" -o jsonpath='{.items[?(@.spec.template.metadata.labels."machine.openshift.io/cluster-api-machine-role"=="worker")].metadata.name}')

if [ -z "$DEFAULT_WORKER_MS_NAME" ]; then
    echo "[ERROR] Could not find the default worker MachineSet. This is unexpected after a successful IPI installation."
    exit 1
fi
echo "[INFO] Found default worker MachineSet: ${DEFAULT_WORKER_MS_NAME}"


# --- Step 3: Determine the vSphere VM Template to use ---
# Check if user has provided a template name override in dr.vars.
# If not, detect it automatically from the default worker machineset we just found.
if [ -n "${OCP_VSPHERE_VM_TEMPLATE}" ]; then
    echo "[INFO] Using user-provided vSphere Template from dr.vars: ${OCP_VSPHERE_VM_TEMPLATE}"
else
    echo "[INFO] OCP_VSPHERE_VM_TEMPLATE is not set. Detecting it automatically..."
    DYNAMIC_TEMPLATE_NAME=$(oc get machineset.machine.openshift.io ${DEFAULT_WORKER_MS_NAME} -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.template}')
    if [ -n "$DYNAMIC_TEMPLATE_NAME" ]; then
        echo "[INFO] Dynamically detected vSphere Template: ${DYNAMIC_TEMPLATE_NAME}"
        export OCP_VSPHERE_VM_TEMPLATE=${DYNAMIC_TEMPLATE_NAME}
    else
        echo "[ERROR] Could not detect vSphere template automatically. Please set OCP_VSPHERE_VM_TEMPLATE in dr.vars manually."
        exit 1
    fi
fi


# --- Step 4: Scale Existing Worker MachineSet ---
echo "[ACTION] Scaling the existing worker MachineSet '${DEFAULT_WORKER_MS_NAME}' to ${OCP_WORKER_NODE_REPLICAS} replicas."
oc scale machineset.machine.openshift.io ${DEFAULT_WORKER_MS_NAME} -n openshift-machine-api --replicas=${OCP_WORKER_NODE_REPLICAS}


# --- Step 5: Create New Infra and Infra-ODF MachineSets ---
create_machineset() {
    export MACHINE_ROLE=$1
    export REPLICAS=$2
    export NUM_CPUS=$3
    export MEMORY_MIB=$4
    export DISK_GIB=$5
    export NODE_LABEL_KEY=${6}
    export NODE_LABEL_VALUE=${7}

    echo "[ACTION] Creating MachineSet for role: ${MACHINE_ROLE}"
    envsubst < ../dr-bootstrap/nodes/01_machineset.yaml.template | oc apply -f -
}

create_machineset "infra" ${OCP_INFRA_NODE_REPLICAS} ${OCP_INFRA_NODE_CPU} ${OCP_INFRA_NODE_MEMORY} ${OCP_INFRA_NODE_DISK_GB} "node-role.kubernetes.io/infra" ""
create_machineset "infra-odf" ${OCP_INFRA_ODF_NODE_REPLICAS} ${OCP_INFRA_ODF_NODE_CPU} ${OCP_INFRA_ODF_NODE_MEMORY} ${OCP_INFRA_ODF_NODE_DISK_GB} "cluster.ocs.openshift.io/openshift-storage" ""


# --- Step 6: Apply Taints to Infra Nodes ---
echo "[ACTION] Applying MachineConfig to taint 'infra' nodes."
oc apply -f ../dr-bootstrap/nodes/02_machineconfig-infra-taint.yaml


# --- Step 7: Wait for All Nodes to Become Ready ---
echo "[INFO] Waiting for all worker, infra, and infra-odf nodes to be created and become 'Ready'..."
echo "[INFO] This can take 15-30 minutes depending on the vSphere environment."

TOTAL_NODES_EXPECTED=$((OCP_WORKER_NODE_REPLICAS + OCP_INFRA_NODE_REPLICAS + OCP_INFRA_ODF_NODE_REPLICAS))
while true; do
    READY_NODES=$(oc get nodes -l 'node-role.kubernetes.io/worker=' -o json | jq '[.items[] | select(.status.conditions[] | .type == "Ready" and .status == "True")] | length')
    
    echo "Current ready worker/infra nodes: ${READY_NODES:-0} / ${TOTAL_NODES_EXPECTED}"
    
    if [[ "${READY_NODES:-0}" -ge "$TOTAL_NODES_EXPECTED" ]]; then
        echo "[SUCCESS] All ${TOTAL_NODES_EXPECTED} nodes are now in 'Ready' state."
        break
    fi
    sleep 60
done

echo "--- Node Provisioning Finished Successfully ---"