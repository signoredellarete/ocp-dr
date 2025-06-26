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

# Function to check resource status
check_status() {
    local component=$1
    local command_to_run=$2
    local expected_status=$3
    local check_name=$4

    echo -e "\n${YELLOW}Checking: ${component}...${NC}"
    
    # Run the command and capture the output
    output=$(eval "$command_to_run")
    
    # Check if any item does NOT match the expected status
    if echo "$output" | grep -v "$expected_status"; then
        echo -e "[ ${RED}FAIL${NC} ] One or more '${component}' components are not in the '${expected_status}' state."
        echo "------"
        echo "$output"
        echo "------"
        OVERALL_STATUS=1
    else
        echo -e "[ ${GREEN}OK${NC} ] All '${component}' components are '${expected_status}'."
    fi
}

# 1. Check ClusterOperators
check_status "ClusterOperators" \
             "oc get co -o custom-columns=NAME:.metadata.name,AVAILABLE:.status.conditions[?(@.type=='Available')].status,PROGRESSING:.status.conditions[?(@.type=='Progressing')].status,DEGRADED:.status.conditions[?(@.type=='Degraded')].status | grep -v 'True.*True.*True'" \
             "" \
             "Not Degraded/Progressing"

# 2. Check Node Status
check_status "Nodes" \
             "oc get nodes --no-headers | awk '{print \$2}'" \
             "Ready" \
             "Nodes are Ready"

# 3. Check Core Operator Pods
echo -e "\n${YELLOW}Checking Core Operator Pod Health...${NC}"
NAMESPACES="openshift-local-storage open-cluster-management openshift-storage openshift-gitops openshift-sso"
for ns in $NAMESPACES; do
    echo " -> Namespace: $ns"
    if ! oc get pods -n $ns --no-headers | grep -v "Running\|Completed"; then
        echo -e "    [ ${GREEN}OK${NC} ] All pods are Running or Completed."
    else
        echo -e "    [ ${RED}FAIL${NC} ] Some pods in namespace '$ns' are not Running/Completed:"
        oc get pods -n $ns | grep -v "Running\|Completed"
        OVERALL_STATUS=1
    fi
done

# 4. Check for ODF StorageClasses
echo -e "\n${YELLOW}Checking for StorageClasses...${NC}"
if oc get sc local-sc-for-odf &>/dev/null && oc get sc ocs-storagecluster-ceph-rbd &>/dev/null; then
    echo -e "[ ${GREEN}OK${NC} ] Required StorageClasses (local-sc-for-odf, ocs-storagecluster-ceph-rbd) found."
else
    echo -e "[ ${RED}FAIL${NC} ] One or more required StorageClasses are missing."
    OVERALL_STATUS=1
fi

# Final Summary
echo -e "\n--- Validation Summary ---"
if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "[ ${GREEN}SUCCESS${NC} ] The OpenShift DR cluster infrastructure appears to be healthy and ready."
else
    echo -e "[ ${RED}FAILURE${NC} ] The validation script found one or more issues. Please review the logs above."
    exit 1
fi