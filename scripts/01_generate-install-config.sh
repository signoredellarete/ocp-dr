#!/bin/bash
set -e

# Load environment variables from config file
source ../ocp_configs/dr.vars

echo "--- Generating install-config.yaml for DR ---"

# Export file contents to be used by envsubst
export OCP_PULL_SECRET_CONTENT=$(cat ${OCP_PULL_SECRET_PATH} | tr -d '\r\n')
export OCP_SSH_KEY_CONTENT=$(cat ${OCP_SSH_KEY_PATH})

# Verify the template file exists
TEMPLATE_FILE="../ocp_configs/install-config.yaml.template"
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "[ERROR] Template file not found at $TEMPLATE_FILE"
    exit 1
fi

# Ensure the installation directory exists
mkdir -p ${OCP_INSTALL_DIR}

# Generate the final install-config.yaml by substituting variables
envsubst < ${TEMPLATE_FILE} > ${OCP_INSTALL_DIR}/install-config.yaml

echo "[SUCCESS] Successfully generated ${OCP_INSTALL_DIR}/install-config.yaml."

# --- Create a pre-installation backup of the generated configuration ---
echo "[INFO] Creating pre-installation backup of the generated configuration."

# Ensure the main backup directory exists
mkdir -p "${OCP_INSTALL_DIR_BACKUP}"

# Define a unique, timestamped name for this configuration snapshot
BACKUP_SNAPSHOT_NAME="install-dir-snapshot-$(date +%Y%m%d-%H%M%S)"
BACKUP_SNAPSHOT_PATH="${OCP_INSTALL_DIR_BACKUP}/${BACKUP_SNAPSHOT_NAME}"

echo "[ACTION] Copying '${OCP_INSTALL_DIR}' to '${BACKUP_SNAPSHOT_PATH}'"

# Use 'cp -a' to preserve all attributes and copy the directory
cp -a "${OCP_INSTALL_DIR}" "${BACKUP_SNAPSHOT_PATH}"

if [ $? -eq 0 ]; then
    echo "[SUCCESS] Pre-installation backup created successfully."
else
    echo "[ERROR] Failed to create pre-installation backup. Aborting."
    exit 1
fi
# --- End of backup section ---