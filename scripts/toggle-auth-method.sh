#!/bin/bash
# Flight Tracker - Toggle Authentication Method
# Switch between Shared Key and Azure AD authentication for storage access

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Toggle Storage Authentication Method${NC}"
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

# Check current authentication method
echo -e "${YELLOW}Checking current authentication method...${NC}"
CURRENT_KEY=$(az staticwebapp appsettings list \
    --name "$STATIC_WEB_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --query "properties.AZURE_STORAGE_KEY" -o tsv 2>/dev/null || echo "")

if [ -z "$CURRENT_KEY" ] || [ "$CURRENT_KEY" == "null" ]; then
    CURRENT_METHOD="Azure AD"
    echo -e "Current method: ${BLUE}Azure AD (Managed Identity)${NC}"
else
    CURRENT_METHOD="Shared Key"
    echo -e "Current method: ${BLUE}Shared Key${NC}"
fi
echo

# Prompt for action
if [ "$CURRENT_METHOD" == "Shared Key" ]; then
    echo -e "${YELLOW}Currently using SHARED KEY authentication${NC}"
    echo -e "${YELLOW}Do you want to switch to AZURE AD authentication? (y/N)${NC}"
    read -r RESPONSE
    
    if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Removing storage key from app settings...${NC}"
        az staticwebapp appsettings delete \
            --name "$STATIC_WEB_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --setting-names AZURE_STORAGE_KEY \
            --output none 2>/dev/null || {
                echo -e "${YELLOW}Key may not exist${NC}"
            }
        
        echo -e "${GREEN}✓ Switched to Azure AD authentication${NC}"
        echo
        echo -e "${YELLOW}Note:${NC}"
        echo "  • API will use Azure AD (DefaultAzureCredential)"
        echo "  • For Free tier, this uses Azure CLI credentials in Functions"
        echo "  • You may need to ensure shared key access is enabled on storage"
        echo "  • For production, upgrade to Standard tier for Managed Identity"
        echo
        echo -e "${YELLOW}Next step:${NC}"
        echo "  Redeploy the dashboard: ${BLUE}./scripts/deploy-dashboard.sh${NC}"
    else
        echo -e "${YELLOW}No changes made${NC}"
    fi
else
    echo -e "${YELLOW}Currently using AZURE AD authentication${NC}"
    echo -e "${YELLOW}Do you want to switch to SHARED KEY authentication? (y/N)${NC}"
    read -r RESPONSE
    
    if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
        if [ -z "$AZURE_STORAGE_KEY" ]; then
            echo -e "${RED}Error: AZURE_STORAGE_KEY not found in azure-config.env${NC}"
            echo "Please run ./scripts/setup-azure.sh first to generate the key"
            exit 1
        fi
        
        echo -e "${YELLOW}Adding storage key to app settings...${NC}"
        az staticwebapp appsettings set \
            --name "$STATIC_WEB_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --setting-names AZURE_STORAGE_KEY="$AZURE_STORAGE_KEY" \
            --output none
        
        echo -e "${GREEN}✓ Switched to Shared Key authentication${NC}"
        echo
        echo -e "${YELLOW}Note:${NC}"
        echo "  • API will use storage account key"
        echo "  • This works on all Static Web App tiers"
        echo "  • Ensure shared key access is enabled on storage account"
        echo
        echo -e "${YELLOW}Next step:${NC}"
        echo "  Redeploy the dashboard: ${BLUE}./scripts/deploy-dashboard.sh${NC}"
    else
        echo -e "${YELLOW}No changes made${NC}"
    fi
fi

echo
echo -e "${GREEN}✓ Operation complete${NC}"
