#!/bin/bash
# Flight Tracker - Toggle Azure Storage Shared Key Access
# Enables or disables shared key authorization for Azure Storage Account

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Azure Storage - Shared Key Toggle${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Check if azure-config.env exists
if [ ! -f azure-config.env ]; then
    echo -e "${RED}Error: azure-config.env not found${NC}"
    echo "Please run ./scripts/setup-azure.sh first"
    exit 1
fi

# Load configuration
source azure-config.env

echo -e "${YELLOW}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Storage Account: $AZURE_STORAGE_ACCOUNT"
echo

# Check current status
echo -e "${YELLOW}Checking current shared key access status...${NC}"
CURRENT_STATUS=$(az storage account show \
    --name "$AZURE_STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "allowSharedKeyAccess" -o tsv)

echo -e "Current status: ${BLUE}$CURRENT_STATUS${NC}"
echo

# Prompt for action
if [ "$CURRENT_STATUS" == "true" ]; then
    echo -e "${YELLOW}Shared key access is currently ENABLED${NC}"
    echo -e "${YELLOW}Do you want to DISABLE it? (y/N)${NC}"
    read -r RESPONSE
    
    if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Disabling shared key access...${NC}"
        az storage account update \
            --name "$AZURE_STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --allow-shared-key-access false \
            --output none
        
        echo -e "${GREEN}✓ Shared key access disabled${NC}"
        echo
        echo -e "${YELLOW}Note:${NC}"
        echo "  • Storage account keys can no longer be used for authentication"
        echo "  • SAS tokens based on shared keys will not work"
        echo "  • You must use Azure AD (Entra ID) authentication"
        echo "  • The dashboard API will need to be updated to use Managed Identity"
    else
        echo -e "${YELLOW}No changes made${NC}"
    fi
else
    echo -e "${YELLOW}Shared key access is currently DISABLED${NC}"
    echo -e "${YELLOW}Do you want to ENABLE it? (y/N)${NC}"
    read -r RESPONSE
    
    if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Enabling shared key access...${NC}"
        az storage account update \
            --name "$AZURE_STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --allow-shared-key-access true \
            --output none
        
        echo -e "${GREEN}✓ Shared key access enabled${NC}"
        echo
        echo -e "${YELLOW}Note:${NC}"
        echo "  • Storage account keys can now be used for authentication"
        echo "  • SAS tokens based on shared keys will work"
        echo "  • The current dashboard API configuration will work"
    else
        echo -e "${YELLOW}No changes made${NC}"
    fi
fi

echo
echo -e "${GREEN}✓ Operation complete${NC}"
