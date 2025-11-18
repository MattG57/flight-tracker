#!/bin/bash
# Flight Tracker - Enable Managed Identity and Grant Storage Access
# Configures the Static Web App to use Managed Identity for storage access

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Enable Managed Identity for Static Web App${NC}"
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
echo "  Static Web App: $STATIC_WEB_APP"
echo

# Enable system-assigned managed identity on Static Web App
echo -e "${YELLOW}Enabling system-assigned managed identity...${NC}"
PRINCIPAL_ID=$(az staticwebapp identity assign \
    --name "$STATIC_WEB_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --query "principalId" -o tsv 2>/dev/null || echo "")

if [ -z "$PRINCIPAL_ID" ]; then
    echo -e "${YELLOW}Checking if identity already exists...${NC}"
    PRINCIPAL_ID=$(az staticwebapp show \
        --name "$STATIC_WEB_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query "identity.principalId" -o tsv 2>/dev/null || echo "")
fi

if [ -z "$PRINCIPAL_ID" ]; then
    echo -e "${RED}Error: Failed to enable or retrieve managed identity${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Managed identity enabled${NC}"
echo -e "  Principal ID: ${BLUE}$PRINCIPAL_ID${NC}"
echo

# Get storage account ID
echo -e "${YELLOW}Getting storage account resource ID...${NC}"
STORAGE_ID=$(az storage account show \
    --name "$AZURE_STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "id" -o tsv)

echo -e "${GREEN}✓ Storage account found${NC}"
echo

# Assign Storage Blob Data Contributor role
echo -e "${YELLOW}Assigning 'Storage Blob Data Contributor' role...${NC}"
az role assignment create \
    --assignee "$PRINCIPAL_ID" \
    --role "Storage Blob Data Contributor" \
    --scope "$STORAGE_ID" \
    --output none 2>/dev/null || {
        echo -e "${YELLOW}Role may already be assigned${NC}"
    }

echo -e "${GREEN}✓ Role assigned${NC}"
echo

# Wait for role assignment to propagate
echo -e "${YELLOW}Waiting for role assignment to propagate (30 seconds)...${NC}"
sleep 30

echo -e "${GREEN}✓ Managed identity configured${NC}"
echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Configuration Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Deploy the updated API code:"
echo "     ${BLUE}./scripts/deploy-dashboard.sh${NC}"
echo
echo "  2. (Optional) Disable shared key access:"
echo "     ${BLUE}./scripts/toggle-shared-key.sh${NC}"
echo
echo -e "${YELLOW}Note:${NC}"
echo "  • The Static Web App now uses Managed Identity"
echo "  • AZURE_STORAGE_KEY is no longer needed"
echo "  • The API will authenticate using Azure AD"
echo "  • You can now safely disable shared key access"
echo
