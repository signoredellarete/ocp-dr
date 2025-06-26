#!/bin/bash
set -e

# Load environment variables
source ../ocp_configs/dr.vars

echo "--- Starting ACM Channel and Secret Generation ---"

# --- Pre-checks ---
echo "[INFO] Performing pre-checks on the Git repository..."

# Construct the credentialed URL for git operations
GIT_HOST_PATH=$(echo "${ACM_GIT_CHANNEL_REPO_URL}" | sed -e 's|https://||')
CREDENTIALED_URL="https://${ACM_GIT_CHANNEL_USERNAME}:${ACM_GIT_CHANNEL_ACCESS_TOKEN}@${GIT_HOST_PATH}"

# 1. Test Git connection using credentials
echo "[ACTION] Testing connection to Git repository..."
if git ls-remote "${CREDENTIALED_URL}" > /dev/null 2>&1; then
    echo "[SUCCESS] Git repository connection successful."
else
    echo "[ERROR] Failed to connect to Git repository. Check URL, username, and token in dr.vars."
    exit 1
fi

# 2. Check for kustomization.yaml file within the repo
# Create a temporary directory for cloning
TEMP_DIR=$(mktemp -d)
# Ensure the temp directory is cleaned up on script exit
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "[ACTION] Cloning repository to verify file existence..."
git clone --quiet "${CREDENTIALED_URL}" "$TEMP_DIR"

KUSTOMIZE_FILE_PATH="${TEMP_DIR}/hub-cluster-config/overlays/hub-dr-cluster/kustomization.yaml"
if [ -f "$KUSTOMIZE_FILE_PATH" ]; then
    echo "[SUCCESS] Required file 'kustomization.yaml' found in repository."
else
    echo "[ERROR] Required file 'kustomization.yaml' not found at expected path in the repository."
    exit 1
fi


# --- YAML Generation ---
echo "[INFO] All checks passed. Generating YAML file..."

# Base64 encode the credentials for the Kubernetes Secret
export ACM_GIT_CHANNEL_USERNAME_B64=$(echo -n "${ACM_GIT_CHANNEL_USERNAME}" | base64)
export ACM_GIT_CHANNEL_ACCESS_TOKEN_B64=$(echo -n "${ACM_GIT_CHANNEL_ACCESS_TOKEN}" | base64)

# Define template and output files
TEMPLATE_FILE="../dr-bootstrap/acm/03_channel.yaml.template"
OUTPUT_FILE="../dr-bootstrap/acm/03_channel.yaml"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "[ERROR] Template file not found at: ${TEMPLATE_FILE}"
    exit 1
fi

# Substitute variables and create the final YAML file
envsubst < "${TEMPLATE_FILE}" > "${OUTPUT_FILE}"

# --- Final Confirmation ---
echo "[SUCCESS] YAML file '${OUTPUT_FILE}' has been created."
echo "You can now use this file in your main bootstrap process."