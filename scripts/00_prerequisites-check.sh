#!/bin/bash

# Load environment variables
source ../ocp_configs/dr.vars

# --- Color Codes ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "--- Starting DR Prerequisites Check ---"

# Function to check command existence
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "[ ${GREEN}OK${NC} ] Command '$1' is installed."
    else
        echo -e "[ ${RED}FAIL${NC} ] Command '$1' is NOT installed. Please install it."
        exit 1
    fi
}

# Function to check TCP connectivity
check_connection() {
    if nc -zv -w 5 $1 $2 &> /dev/null; then
        echo -e "[ ${GREEN}OK${NC} ] Can connect to $1 on port $2."
    else
        echo -e "[ ${RED}FAIL${NC} ] Cannot connect to $1 on port $2. Check network/firewall."
        exit 1
    fi
}

# 1. Check for required tools
echo -e "\n${YELLOW}1. Verifying required tools...${NC}"
check_command "openshift-install"
check_command "oc"
check_command "git"
check_command "nc"
check_command "envsubst"

# 2. Check for required files
echo -e "\n${YELLOW}2. Verifying required configuration files...${NC}"
if [ -f "$OCP_PULL_SECRET_PATH" ]; then
    echo -e "[ ${GREEN}OK${NC} ] Pull secret found at $OCP_PULL_SECRET_PATH."
else
    echo -e "[ ${RED}FAIL${NC} ] Pull secret NOT found at $OCP_PULL_SECRET_PATH."
    exit 1
fi
if [ -f "$OCP_SSH_KEY_PATH" ]; then
    echo -e "[ ${GREEN}OK${NC} ] SSH key found at $OCP_SSH_KEY_PATH."
else
    echo -e "[ ${RED}FAIL${NC} ] SSH key NOT found at $OCP_SSH_KEY_PATH."
    exit 1
fi

# 3. Check network connectivity to critical services
echo -e "\n${YELLOW}3. Verifying network connectivity...${NC}"
check_connection $VSPHERE_SERVER 443
check_connection $GIT_SERVER 22
check_connection $QUAY_SERVER 443

# 4. Check DNS Resolution (optional, but recommended)
echo -e "\n${YELLOW}4. Verifying DNS resolution...${NC}"
if getent hosts $VSPHERE_SERVER &> /dev/null; then
    echo -e "[ ${GREEN}OK${NC} ] DNS resolves for $VSPHERE_SERVER."
else
    echo -e "[ ${RED}FAIL${NC} ] DNS does not resolve for $VSPHERE_SERVER."
    exit 1
fi


echo -e "\n--- ${GREEN}Prerequisites Check Completed Successfully!${NC} ---"