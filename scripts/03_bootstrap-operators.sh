#!/bin/bash
set -e

# Source dr.vars
source ../ocp_configs/dr.vars

# Set KUBECONFIG
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

# Apply manifests for GitOps application Subscription
oc apply -f ../dr-bootstrap/acm/03_application.yaml
oc apply -f ../dr-bootstrap/acm/04_placement.yaml
oc apply -f ../dr-bootstrap/acm/05_subscription.yaml

if [ $? -eq 0 ]; then
    echo "Hub Infrastructure Application bootstrapped."
    echo "ACM will now connect to the Git repository and apply the Kustomize configuration."
else
    echo -e "[ERROR] Failed to apply the ACM Application manifests."
    exit 1
fi

echo "--- Operator Bootstrap Script Finished ---"