#!/bin/bash
set -e

# Load environment variables from config file
source ../ocp_configs/dr.vars

# Set KUBECONFIG to connect to the new cluster
export KUBECONFIG=${OCP_INSTALL_DIR}/auth/kubeconfig

echo "--- Bootstrapping Infrastructure Operators (ACM Only) ---"

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

# Create the target namespace first
echo "[ACTION] Ensuring namespace 'open-cluster-management' exists..."
oc apply -f ../dr-bootstrap/acm/00_namespace.yaml

# --- RIGA AGGIUNTA ---
# Create the OperatorGroup in the namespace
echo "[ACTION] Applying OperatorGroup..."
oc apply -f ../dr-bootstrap/acm/01_operatorgroup.yaml

# Now apply the subscription into the configured namespace
echo "[ACTION] Applying ACM Subscription..."
oc apply -f ../dr-bootstrap/acm/02_subscription.yaml

wait_for_operator "open-cluster-management"

echo "Applying MultiClusterHub configuration..."
oc apply -f ../dr-bootstrap/acm/03_multiclusterhub.yaml

echo "Waiting for MultiClusterHub to be available..."
until oc get mch -n open-cluster-management multiclusterhub -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; do
    sleep 20
    echo -n "."
done
echo " MultiClusterHub is running."

# --- 2. Apply the ACM Application that points to the Kustomize Git Repo ---
echo -e "\n--- Applying ACM Application to enable GitOps ---"

# Apply all manifests that define our GitOps Application
oc apply -f ../dr-bootstrap/acm/04_application.yaml
oc apply -f ../dr-bootstrap/acm/05_placement.yaml
oc apply -f ../dr-bootstrap/acm/06_subscription.yaml

if [ $? -eq 0 ]; then
    echo "Hub Infrastructure Application bootstrapped."
    echo "ACM will now connect to the Git repository and apply the Kustomize configuration."
else
    echo -e "[ERROR] Failed to apply the ACM Application manifests."
    exit 1
fi

echo "--- Operator Bootstrap Script Finished ---"