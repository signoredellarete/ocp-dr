#!/bin/bash
set -e

# Load environment variables
source ../ocp_configs/dr.vars

echo "--- Generating install-config.yaml for DR ---"

# Export file contents to be used by envsubst
export OCP_PULL_SECRET_CONTENT=$(cat ${OCP_PULL_SECRET_PATH} | tr -d '\r\n')
export OCP_SSH_KEY_CONTENT=$(cat ${OCP_SSH_KEY_PATH})

# Find the template file
TEMPLATE_FILE="../ocp_configs/install-config.yaml.template"
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Template file not found at $TEMPLATE_FILE"
    exit 1
fi

# Create installation directory if it doesn't exist
mkdir -p ${OCP_INSTALL_DIR}

# Substitute variables and create the final install-config.yaml
envsubst < ${TEMPLATE_FILE} > ${OCP_INSTALL_DIR}/install-config.yaml

echo "Successfully generated ${OCP_INSTALL_DIR}/install-config.yaml."
echo "Please review the file before proceeding with cluster creation."