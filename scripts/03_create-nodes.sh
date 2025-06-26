#!/bin/bash
set -e

# Load environment variables from config file
source ../ocp_configs/dr.vars

# Set KUBECONFIG to connect to the new cluster
export KUBECONFIG=${OCP_INSTALL_DIR}/auth/kubeconfig

echo "--- Starting Worker and Infra Node Provisioning ---"

# --- Step 1: Gather Dynamic Information ---
echo "[INFO] Gathering information from the newly created cluster..."
METADATA_FILE="${OCP_INSTALL_DIR}/metadata.json"
if [ ! -f "$METADATA_FILE" ]; then
    echo "[ERROR] Metadata file not found at $METADATA_FILE."
    exit 1
fi
export CLUSTER_ID=$(jq -r .infraID ${METADATA_FILE})
echo "[INFO] Found Infrastructure ID (CLUSTER_ID): ${CLUSTER_ID}"

DEFAULT_WORKER_MS_NAME=$(oc get machineset.machine.openshift.io -n openshift-machine-api -l "machine.openshift.io/cluster-api-cluster=${CLUSTER_ID}" -o jsonpath='{.items[0].metadata.name}')
if [ -z "$DEFAULT_WORKER_MS_NAME" ]; then
    echo "[ERROR] Could not find the default worker MachineSet."
    exit 1
fi
echo "[INFO] Found default worker MachineSet: ${DEFAULT_WORKER_MS_NAME}"

export OCP_VSPHERE_VM_TEMPLATE=$(oc get machineset.machine.openshift.io ${DEFAULT_WORKER_MS_NAME} -n openshift-machine-api -o jsonpath='{.spec.template.spec.providerSpec.value.template}')
echo "[INFO] Using dynamically detected vSphere Template: ${OCP_VSPHERE_VM_TEMPLATE}"


# --- Step 2: Scale Existing Worker MachineSet ---
echo "[ACTION] Scaling the existing worker MachineSet '${DEFAULT_WORKER_MS_NAME}' to ${OCP_WORKER_NODE_REPLICAS} replicas."
oc scale machineset.machine.openshift.io ${DEFAULT_WORKER_MS_NAME} -n openshift-machine-api --replicas=${OCP_WORKER_NODE_REPLICAS}


# --- Step 3: Create New Infra MachineSet ---
echo "[ACTION] Creating MachineSet for 'infra' role..."
envsubst < ../dr-bootstrap/nodes/01_machineset-infra.yaml.template | oc apply -f -


# --- Step 4: Create New Infra-ODF MachineSet ---
echo "[ACTION] Creating MachineSet for 'infra-odf' role..."
envsubst < ../dr-bootstrap/nodes/02_machineset-infra-odf.yaml.template | oc apply -f -


# --- Step 5: Wait for All Nodes to Become Ready ---
echo "[INFO] Waiting for all nodes to be provisioned and become 'Ready'..."
TOTAL_NODES_EXPECTED=$((OCP_WORKER_NODE_REPLICAS + OCP_INFRA_NODE_REPLICAS + OCP_INFRA_ODF_NODE_REPLICAS))
while true; do
    # --- THIS IS THE ONLY MODIFIED LINE ---
    # It now correctly excludes master nodes from the count
    READY_NODES=$(oc get nodes -l 'node-role.kubernetes.io/worker=,node-role.kubernetes.io/master!=' -o json | jq '[.items[] | select(.status.conditions[] | .type == "Ready" and .status == "True")] | length')
    
    echo "Current ready worker/infra nodes: ${READY_NODES:-0} / ${TOTAL_NODES_EXPECTED}"
    if [[ "${READY_NODES:-0}" -ge "$TOTAL_NODES_EXPECTED" ]]; then
        echo "[SUCCESS] All ${TOTAL_NODES_EXPECTED} nodes are now in 'Ready' state."
        break
    fi
    sleep 60
done

echo "--- Node Provisioning Finished Successfully ---"