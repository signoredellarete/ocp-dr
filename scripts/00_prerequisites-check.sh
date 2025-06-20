#!/bin/bash

# Load environment variables
source ../ocp_configs/dr.vars

# --- Color Codes ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "--- Starting DR Prerequisites Check ---"

# --- NEW FUNCTION: Trust vCenter Certificate (Idempotent) ---
trust_vcenter_cert() {
    echo -e "\n${YELLOW}0. Verifying vCenter Certificate Trust...${NC}"

    # Check if we can connect successfully without specifying a CA file
    # If 'Verify return code: 0 (ok)', the cert is already trusted system-wide.
    if echo "Q" | openssl s_client -connect ${VSPHERE_SERVER}:443 2>/dev/null | grep -q "Verify return code: 0 (ok)"; then
        echo -e "[ ${GREEN}OK${NC} ] vCenter certificate is already trusted by the system."
        return 0
    fi

    echo -e "[ ${YELLOW}INFO${NC} ] vCenter certificate is not trusted. Attempting to add it."

    # Check if the certificate file exists
    if [ ! -f "${VSPHERE_CERT_PATH}" ]; then
        echo -e "[ ${RED}FAIL${NC} ] vCenter certificate file not found at: ${VSPHERE_CERT_PATH}"
        exit 1
    fi

    # Copy the certificate and update the trust store
    echo "[ ${YELLOW}ACTION${NC} ] Copying certificate and updating system trust store. This requires sudo."
    
    # Extract filename for the destination
    CERT_FILENAME=$(basename "${VSPHERE_CERT_PATH}")
    
    sudo cp "${VSPHERE_CERT_PATH}" "/etc/pki/ca-trust/source/anchors/${CERT_FILENAME}"
    if [ $? -ne 0 ]; then
        echo -e "[ ${RED}FAIL${NC} ] Failed to copy certificate. Check permissions."
        exit 1
    fi

    sudo update-ca-trust extract
    if [ $? -ne 0 ]; then
        echo -e "[ ${RED}FAIL${NC} ] 'update-ca-trust extract' command failed."
        exit 1
    fi

    echo -e "[ ${YELLOW}INFO${NC} ] System trust store updated. Re-verifying connection..."

    # Re-verify after trusting the certificate
    if echo "Q" | openssl s_client -connect ${VSPHERE_SERVER}:443 2>/dev/null | grep -q "Verify return code: 0 (ok)"; then
        echo -e "[ ${GREEN}OK${NC} ] vCenter certificate is now successfully trusted."
    else
        echo -e "[ ${RED}FAIL${NC} ] Failed to trust the vCenter certificate after update. Please investigate manually."
        exit 1
    fi
}


# ... (le funzioni check_command, check_connection, check_vip_availability rimangono identiche) ...
check_command() { if command -v $1 &>/dev/null; then echo -e "[ ${GREEN}OK${NC} ] Command '$1' is installed."; else echo -e "[ ${RED}FAIL${NC} ] Command '$1' is NOT installed."; exit 1; fi; }
check_connection() { if nc -zv -w 5 $1 $2 &>/dev/null; then echo -e "[ ${GREEN}OK${NC} ] Can connect to $1 on port $2."; else echo -e "[ ${RED}FAIL${NC} ] Cannot connect to $1 on port $2."; exit 1; fi; }
check_vip_availability() { if ! nc -zv -w 5 $1 $2 &>/dev/null; then echo -e "[ ${GREEN}OK${NC} ] VIP $1 on port $2 appears to be free."; else echo -e "[ ${RED}FAIL${NC} ] VIP $1 on port $2 is already in use."; exit 1; fi; }


# --- SCRIPT EXECUTION STARTS HERE ---

# 0. Trust vCenter Certificate (NEW STEP)
trust_vcenter_cert

# 1. Check for required tools
echo -e "\n${YELLOW}1. Verifying required tools...${NC}"
check_command "openshift-install"
check_command "oc"
check_command "git"
check_command "nc"
check_command "envsubst"
check_command "openssl"

# 2. Check for required files
echo -e "\n${YELLOW}2. Verifying required configuration files...${NC}"
# ... (questa sezione rimane invariata) ...
if [ -f "$OCP_PULL_SECRET_PATH" ]; then echo -e "[ ${GREEN}OK${NC} ] Pull secret found at $OCP_PULL_SECRET_PATH."; else echo -e "[ ${RED}FAIL${NC} ] Pull secret NOT found at $OCP_PULL_SECRET_PATH."; exit 1; fi
if [ -f "$OCP_SSH_KEY_PATH" ]; then echo -e "[ ${GREEN}OK${NC} ] SSH key found at $OCP_SSH_KEY_PATH."; else echo -e "[ ${RED}FAIL${NC} ] SSH key NOT found at $OCP_SSH_KEY_PATH."; exit 1; fi

# 3. Check network connectivity to critical services
echo -e "\n${YELLOW}3. Verifying network connectivity...${NC}"
# ... (questa sezione rimane invariata) ...
check_connection $VSPHERE_SERVER 443
check_connection $GIT_SERVER 22
check_connection $QUAY_SERVER 443

# 4. Check DNS Resolution
echo -e "\n${YELLOW}4. Verifying DNS resolution...${NC}"
# ... (questa sezione rimane invariata) ...
if getent hosts $VSPHERE_SERVER &> /dev/null; then echo -e "[ ${GREEN}OK${NC} ] DNS resolves for $VSPHERE_SERVER."; else echo -e "[ ${RED}FAIL${NC} ] DNS does not resolve for $VSPHERE_SERVER."; exit 1; fi

# 5. Check Virtual IP (VIP) availability
echo -e "\n${YELLOW}5. Verifying Virtual IP availability...${NC}"
# ... (questa sezione rimane invariata) ...
check_vip_availability $OCP_API_VIP 6443
check_vip_availability $OCP_INGRESS_VIP 443
check_vip_availability $OCP_INGRESS_VIP 80


echo -e "\n--- ${GREEN}Prerequisites Check Completed Successfully!${NC} ---"