#!/bin/bash
set -e

# Load environment variables from config file
source ../ocp_configs/dr.vars

# Set KUBECONFIG to connect to the new cluster
export KUBECONFIG=${OCP_INSTALL_DIR}/auth/kubeconfig

echo "--- Bootstrapping Infrastructure Operators (ACM Only) ---"

# ... (funzione wait_for_operator rimane invariata) ...
wait_for_operator() { echo "Waiting for operator in ns $1..."; until oc get csv -n $1 -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Succeeded"; do sleep 15; echo -n "."; done; echo " OK"; }

# --- 1. Install Advanced Cluster Management (ACM) ---
# ... (i passi da 00 a 03 per installare ACM rimangono invariati) ...
echo -e "\n--- Installing Advanced Cluster Management (ACM) ---"
oc apply -f ../dr-bootstrap/acm/00_namespace.yaml
oc apply -f ../dr-bootstrap/acm/01_operatorgroup.yaml
oc apply -f ../dr-bootstrap/acm/02_subscription.yaml
wait_for_operator "open-cluster-management"
oc apply -f ../dr-bootstrap/acm/03_multiclusterhub.yaml
echo "Waiting for MultiClusterHub to be available..."
until oc get mch -n open-cluster-management multiclusterhub -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; do sleep 20; echo -n "."; done
echo " MultiClusterHub is running."

# --- 2. Apply ACM Application and Permissions ---
echo -e "\n--- Applying ACM Application to enable GitOps ---"

# Create the binding to allow the placement rule to see clusters
echo "[ACTION] Creating ManagedClusterSetBinding to grant permissions..."
oc apply -f ../dr-bootstrap/acm/04_managedclustersetbinding.yaml

# Apply all manifests that define our GitOps Application
echo "[ACTION] Applying ACM Application, Placement, Channel, and Subscription..."
oc apply -f ../dr-bootstrap/acm/05_application.yaml
oc apply -f ../dr-bootstrap/acm/06_placement.yaml
# --- RIGHE MODIFICATE ---
oc apply -f ../dr-bootstrap/acm/07_channel.yaml
oc apply -f ../dr-bootstrap/acm/08_subscription.yaml

if [ $? -eq 0 ]; then
    echo "[SUCCESS] Hub Infrastructure Application bootstrapped."
    echo "ACM will now connect to the Git repository and apply the Kustomize configuration."
else
    echo -e "[ERROR] Failed to apply the ACM Application manifests."
    exit 1
fi

echo "--- Operator Bootstrap Script Finished ---"