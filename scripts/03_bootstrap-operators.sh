#!/bin/bash
set -e

# Load environment variables from config file
source ../ocp_configs/dr.vars

# Set KUBECONFIG to connect to the new cluster
export KUBECONFIG=${OCP_INSTALL_DIR}/auth/kubeconfig

echo "--- Bootstrapping Infrastructure Operators (ACM Only) ---"

# Function to wait for an operator's CSV to report Succeeded status
wait_for_operator() {
    echo "Waiting for operator in ns $1..."
    until oc get csv -n $1 -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Succeeded"; do
        sleep 15
        echo -n "."
    done
    echo " OK"
}

# --- 1. Install Advanced Cluster Management (ACM) ---
echo -e "\n--- Installing Advanced Cluster Management (ACM) ---"

# Step 1.1: Create the target namespace
echo "[ACTION] Ensuring namespace 'open-cluster-management' exists..."
oc apply -f ../dr-bootstrap/acm/00_namespace.yaml

# Step 1.2: Create the OperatorGroup in the namespace
echo "[ACTION] Applying OperatorGroup..."
oc apply -f ../dr-bootstrap/acm/01_operatorgroup.yaml

# Step 1.3: Apply the subscription to install the operator
echo "[ACTION] Applying ACM Subscription..."
oc apply -f ../dr-bootstrap/acm/02_subscription.yaml

# Step 1.4: Wait for the operator to be ready
wait_for_operator "open-cluster-management"

# Step 1.5: Apply the MultiClusterHub CR to start the ACM instance
echo "[ACTION] Applying MultiClusterHub configuration..."
oc apply -f ../dr-bootstrap/acm/03_multiclusterhub.yaml

# Step 1.6: Wait for the MultiClusterHub instance to be running
echo "Waiting for MultiClusterHub to be available..."
until oc get mch -n open-cluster-management multiclusterhub -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; do
    sleep 20
    echo -n "."
done
echo " MultiClusterHub is running."

# --- 2. Apply ACM Application and Permissions ---
echo -e "\n--- Applying ACM Application to enable GitOps ---"

# Step 2.1: Create the binding to allow the placement rule to see clusters
echo "[ACTION] Creating ManagedClusterSetBinding to grant placement permissions..."
oc apply -f ../dr-bootstrap/acm/04_managedclustersetbinding.yaml

# Step 2.2: Apply all manifests that define our GitOps Application
echo "[ACTION] Applying ACM Application, Placement, and Subscription..."
oc apply -f ../dr-bootstrap/acm/05_application.yaml
oc apply -f ../dr-bootstrap/acm/06_placement.yaml
oc apply -f ../dr-bootstrap/acm/07_subscription.yaml

if [ $? -eq 0 ]; then
    echo "[SUCCESS] Hub Infrastructure Application bootstrapped."
    echo "ACM will now connect to the Git repository and apply the Kustomize configuration."
else
    echo -e "[ERROR] Failed to apply the ACM Application manifests."
    exit 1
fi

echo "--- Operator Bootstrap Script Finished ---"