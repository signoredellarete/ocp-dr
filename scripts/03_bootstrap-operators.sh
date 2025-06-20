#!/bin/bash
set -e

# Load environment variables and set kubeconfig
source ../ocp_configs/dr.vars
export KUBECONFIG=${OCP_INSTALL_DIR}/auth/kubeconfig

echo "--- Bootstrapping Infrastructure Operators (ACM Only) ---"

# Function to wait for a CRD to be established
wait_for_crd() {
    echo "Waiting for CRD $1 to be established..."
    until oc get crd $1 &> /dev/null; do
        sleep 15
        echo -n "."
    done
    echo " CRD $1 is available."
}

# Function to wait for an operator to be ready
wait_for_operator() {
    echo "Waiting for operator in namespace $1 to be ready..."
    # Loop until the CSV status is Succeeded
    until oc get csv -n $1 -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Succeeded"; do
        sleep 15
        echo -n "."
    done
    echo " Operator in namespace $1 is ready."
}

# --- 1. Install Advanced Cluster Management (ACM) ---
echo -e "\n--- Installing Advanced Cluster Management (ACM) ---"
# ACM creates its own namespace via the subscription
oc apply -f ../dr-bootstrap/acm/01_subscription.yaml
wait_for_operator "open-cluster-management"

echo "Applying MultiClusterHub configuration..."
oc apply -f ../dr-bootstrap/acm/02_multiclusterhub.yaml

echo "Waiting for MultiClusterHub to be available (this can take several minutes)..."
until oc get mch -n open-cluster-management multiclusterhub -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; do
    sleep 20
    echo -n "."
done
echo " MultiClusterHub is running."


# --- 2. Apply Initial Hub Policy ---
echo -e "\n--- Applying Initial Policy to let ACM manage itself ---"
# This policy tells ACM to look at the Git repo for its own configuration
oc apply -f ../dr-bootstrap/acm/03_hub-cluster-policy.yaml

echo "ACM installation is complete."
echo "From this point, ACM's GitOps engine will take over."
echo "Monitor the 'local-cluster' policies in the ACM console to see progress on LSO, ODF, etc."

echo "--- Operator Bootstrap Script Finished ---"