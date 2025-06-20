#!/bin/bash
set -e

# Load environment variables and set kubeconfig
source ../ocp_configs/dr.vars
export KUBECONFIG=${OCP_INSTALL_DIR}/auth/kubeconfig

echo "--- Bootstrapping Infrastructure Operators ---"

# Function to wait for a resource to be established
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
    until oc get csv -n $1 -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Succeeded"; do
        sleep 15
        echo -n "."
    done
    echo " Operator in namespace $1 is ready."
}

# --- 1. Install Local Storage Operator (LSO) ---
echo -e "\n--- Installing Local Storage Operator (LSO) ---"
oc apply -f ../dr-bootstrap/lso/01_namespace.yaml
oc apply -f ../dr-bootstrap/lso/02_operatorgroup.yaml
oc apply -f ../dr-bootstrap/lso/03_subscription.yaml
wait_for_operator "openshift-local-storage"
echo "Applying LocalVolume configuration..."
oc apply -f ../dr-bootstrap/lso/04_localvolume.yaml
echo "LSO installation complete. Verifying StorageClass..."
until oc get sc local-sc-for-odf &> /dev/null; do
    sleep 10
    echo -n "."
done
echo " StorageClass 'local-sc-for-odf' created successfully."


# --- 2. Install Advanced Cluster Management (ACM) ---
echo -e "\n--- Installing Advanced Cluster Management (ACM) ---"
# ACM creates its own namespace
oc apply -f ../dr-bootstrap/acm/01_subscription.yaml
wait_for_operator "open-cluster-management"
echo "Applying MultiClusterHub configuration..."
oc apply -f ../dr-bootstrap/acm/02_multiclusterhub.yaml
wait_for_crd "multiclusterhubs.operator.open-cluster-management.io"
echo "ACM installation initiated. It will take 20-40 minutes to become fully active."
echo "From this point, ACM will take over the deployment of other operators (ODF, GitOps, SSO) based on the policies in your Git repository."

echo "--- Operator Bootstrap Script Finished ---"