#!/bin/bash
set -e

# Load environment variables and set kubeconfig
source ../ocp_configs/dr.vars
export KUBECONFIG=${OCP_INSTALL_DIR}/auth/kubeconfig

# --- Color Codes ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "\n--- Starting Full Cluster Validation Script ---"

# Flag to track overall status
OVERALL_STATUS=0

# --- 1. Check ClusterOperators ---
echo -e "\n${YELLOW}Checking: ClusterOperator Health...${NC}"
FAILED_COs=0
# Get all ClusterOperators and check their conditions using jq
CO_STATUS=$(oc get co -o json | jq -r '.items[] | .metadata.name + " " + (.status.conditions[] | select(.type=="Available").status) + " " + (.status.conditions[] | select(.type=="Progressing").status) + " " + (.status.conditions[] | select(.type=="Degraded").status)')

while read -r line; do
    NAME=$(echo $line | awk '{print $1}')
    AVAILABLE=$(echo $line | awk '{print $2}')
    PROGRESSING=$(echo $line | awk '{print $3}')
    DEGRADED=$(echo $line | awk '{print $4}')
    
    if [ "$AVAILABLE" != "True" ] || [ "$PROGRESSING" != "False" ] || [ "$DEGRADED" != "False" ]; then
        echo -e "[ ${RED}FAIL${NC} ] ClusterOperator '${NAME}' is not healthy. State: Available=${AVAILABLE}, Progressing=${PROGRESSING}, Degraded=${DEGRADED}"
        FAILED_COs=$((FAILED_COs + 1))
    fi
done <<< "$CO_STATUS"

if [ "$FAILED_COs" -eq 0 ]; then
    echo -e "[ ${GREEN}OK${NC} ] All ClusterOperators are healthy."
else
    OVERALL_STATUS=1
fi

# --- 2. Check Node Status ---
echo -e "\n${YELLOW}Checking: Node Health...${NC}"
NON_READY_NODES=$(oc get nodes -l 'node-role.kubernetes.io/master!=' -o json | jq -r '[.items[] | select(.status.conditions[] | .type=="Ready" and .status!="True")] | .[] | .metadata.name')

if [ -z "$NON_READY_NODES" ]; then
    echo -e "[ ${GREEN}OK${NC} ] All worker/infra nodes are in 'Ready' state."
else
    echo -e "[ ${RED}FAIL${NC} ] The following nodes are not Ready:"
    echo "$NON_READY_NODES"
    OVERALL_STATUS=1
fi

# --- 3. Check Core Operator Pods ---
echo -e "\n${YELLOW}Checking: Core Operator Pod Health...${NC}"
# --- MODIFIED --- Replaced 'openshift-sso' with 'keycloak'
NAMESPACES_TO_CHECK="openshift-local-storage open-cluster-management openshift-storage openshift-gitops keycloak"
for ns in $NAMESPACES_TO_CHECK; do
    echo -n " -> Namespace: $ns ... "
    # Check if the namespace exists first
    if ! oc get ns "$ns" &> /dev/null; then
        echo -e "[ ${YELLOW}SKIP${NC} ] Namespace does not exist. This is OK if the operator is not yet deployed."
        continue
    fi
    
    # Get pods that are not Running or Completed
    PROBLEM_PODS=$(oc get pods -n "$ns" --no-headers 2>/dev/null | grep -v "Running" | grep -v "Completed" || true)
    
    if [ -z "$PROBLEM_PODS" ]; then
        echo -e "[ ${GREEN}OK${NC} ]"
    else
        echo -e "[ ${RED}FAIL${NC} ]"
        echo "$PROBLEM_PODS"
        OVERALL_STATUS=1
    fi
done

# --- 4. Check ACM and ODF Health ---
echo -e "\n${YELLOW}Checking: ACM and ODF Custom Resource Health...${NC}"
# Check MultiClusterHub status
MCH_PHASE=$(oc get mch -n open-cluster-management multiclusterhub -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$MCH_PHASE" == "Running" ]; then
    echo -e "[ ${GREEN}OK${NC} ] MultiClusterHub status is 'Running'."
else
    echo -e "[ ${RED}FAIL${NC} ] MultiClusterHub status is '${MCH_PHASE:-Not Found}'."
    OVERALL_STATUS=1
fi

# Check StorageCluster status (most important ODF check)
STORAGECLUSTER_PHASE=$(oc get storagecluster -n openshift-storage -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [ "$STORAGECLUSTER_PHASE" == "Ready" ]; then
    echo -e "[ ${GREEN}OK${NC} ] ODF StorageCluster status is 'Ready'."
else
    # This check is allowed to fail if ODF is not yet installed
    echo -e "[ ${YELLOW}WARN${NC} ] ODF StorageCluster status is '${STORAGECLUSTER_PHASE:-Not Found}'. This is OK if ODF is not yet deployed."
fi

# --- 5. Check for ODF StorageClasses ---
echo -e "\n${YELLOW}Checking: StorageClass Availability...${NC}"
if oc get sc ocs-storagecluster-ceph-rbd &>/dev/null; then
    echo -e "[ ${GREEN}OK${NC} ] ODF StorageClass 'ocs-storagecluster-ceph-rbd' found."
else
    # This check is allowed to fail if ODF is not yet installed
    echo -e "[ ${YELLOW}WARN${NC} ] ODF StorageClass 'ocs-storagecluster-ceph-rbd' is missing. This is OK if ODF is not yet deployed."
fi

# --- Final Summary ---
echo -e "\n--- Validation Summary ---"
if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "[ ${GREEN}SUCCESS${NC} ] The OpenShift DR cluster infrastructure appears to be healthy and ready for handoff."
    exit 0
else
    echo -e "[ ${RED}FAILURE${NC} ] The validation script found one or more issues. Please review the logs above."
    exit 1
fi