#!/bin/bash
set -e

# Load environment variables and set kubeconfig
source ../ocp_configs/dr.vars
export KUBECONFIG=${OCP_INSTALL_DIR}/auth/kubeconfig

echo "--- Bootstrapping Infrastructure Operators (ACM Only) ---"

# ... (le funzioni wait_for_crd e wait_for_operator rimangono invariate) ...
wait_for_crd() { echo "Waiting for CRD $1..."; until oc get crd $1 &>/dev/null; do sleep 15; echo -n "."; done; echo " OK"; }
wait_for_operator() { echo "Waiting for operator in ns $1..."; until oc get csv -n $1 -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Succeeded"; do sleep 15; echo -n "."; done; echo " OK"; }

# --- 1. Install Advanced Cluster Management (ACM) ---
echo -e "\n--- Installing Advanced Cluster Management (ACM) ---"
oc apply -f ../dr-bootstrap/acm/01_subscription.yaml
wait_for_operator "open-cluster-management"
echo "Applying MultiClusterHub configuration..."
oc apply -f ../dr-bootstrap/acm/02_multiclusterhub.yaml
echo "Waiting for MultiClusterHub to be available..."
until oc get mch -n open-cluster-management multiclusterhub -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; do
    sleep 20
    echo -n "."
done
echo " MultiClusterHub is running."

# --- 2. Apply the ACM Application that points to the Kustomize Git Repo ---
echo -e "\n--- Applying ACM Application to enable GitOps ---"

# Applichiamo tutti i manifest che definiscono la nostra applicazione GitOps
oc apply -k ../applications/hub-infra/

if [ $? -eq 0 ]; then
    echo "Hub Infrastructure Application applied successfully."
    echo "ACM will now connect to the Git repository and apply the Kustomize configuration."
else
    echo -e "[ERROR] Failed to apply the ACM Application manifests."
    exit 1
fi

echo "--- Operator Bootstrap Script Finished ---"