#!/bin/bash
set -e

# Load environment variables
source ../ocp_configs/dr.vars

echo "--- Starting OpenShift Cluster Creation ---"
echo "This process will take a significant amount of time."

if [ ! -f "${OCP_INSTALL_DIR}/install-config.yaml" ]; then
    echo "install-config.yaml not found. Please run 01_generate-install-config.sh first."
    exit 1
fi

# Launch the installer
openshift-install create cluster --dir=${OCP_INSTALL_DIR} --log-level=info

# Check for successful completion
if [ $? -eq 0 ]; then
    echo "--- Cluster Creation Completed Successfully! ---"
    echo "kubeconfig is available at ${OCP_INSTALL_DIR}/auth/kubeconfig"
else
    echo "--- Cluster Creation Failed. Check the logs in ${OCP_INSTALL_DIR} for details. ---"
    exit 1
fi