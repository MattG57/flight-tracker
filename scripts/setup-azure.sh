#!/bin/bash
# Flight Tracker - Azure Hello World Setup Script
# This script creates all Azure resources and uploads sample data

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Flight Tracker - Azure Setup${NC}"
echo -e "${GREEN}================================${NC}"
echo

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI not found. Install from: https://docs.microsoft.com/cli/azure/install-azure-cli${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo

# Configuration variables
RESOURCE_GROUP="flight-tracker-rg"
LOCATION="eastus2"
STORAGE_ACCOUNT="flighttracker$(date +%s | tail -c 6)"
CONTAINER_NAME="flight-tracker-data"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo "  Storage Account: $STORAGE_ACCOUNT"
echo

# Check Azure login
echo -e "${YELLOW}Checking Azure login...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Please login to Azure...${NC}"
    az login
fi

SUBSCRIPTION=$(az account show --query "name" -o tsv)
echo -e "${GREEN}✓ Logged in to subscription: $SUBSCRIPTION${NC}"
echo

# Create resource group
echo -e "${YELLOW}Creating resource group...${NC}"
if az group exists --name $RESOURCE_GROUP | grep -q "true"; then
    echo -e "${YELLOW}Resource group already exists${NC}"
else
    az group create --name $RESOURCE_GROUP --location $LOCATION --output none
    echo -e "${GREEN}✓ Resource group created${NC}"
fi
echo

# Create storage account
echo -e "${YELLOW}Creating storage account...${NC}"
az storage account create \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard_LRS \
    --https-only true \
    --output none 2>/dev/null || echo -e "${YELLOW}Storage account may already exist${NC}"

STORAGE_KEY=$(az storage account keys list \
    --account-name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query "[0].value" -o tsv)
echo -e "${GREEN}✓ Storage configured${NC}"
echo

# Create container
echo -e "${YELLOW}Creating blob container...${NC}"
az storage container create \
    --account-name $STORAGE_ACCOUNT \
    --account-key "$STORAGE_KEY" \
    --name $CONTAINER_NAME \
    --output none 2>/dev/null || echo -e "${YELLOW}Container may already exist${NC}"
echo -e "${GREEN}✓ Container created${NC}"
echo

# Upload sample flight
echo -e "${YELLOW}Uploading sample flight...${NC}"
SAMPLE='{"schemaVersion":"1.0.0","flightId":"flight-hello-world","status":"successful","goal":{"type":"explicit","description":"Hello World"},"createdAt":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}'

echo "$SAMPLE" | az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --account-key "$STORAGE_KEY" \
    --container-name $CONTAINER_NAME \
    --name "flights/hello-world.jsonl" \
    --data @- \
    --overwrite \
    --output none

echo -e "${GREEN}✓ Sample flight uploaded${NC}"
echo

# Save config
JWT_SECRET=$(openssl rand -base64 32)
cat > azure-config.env << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
AZURE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT
AZURE_STORAGE_KEY=$STORAGE_KEY
AZURE_STORAGE_CONTAINER=$CONTAINER_NAME
JWT_SECRET=$JWT_SECRET
EOF

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo -e "${YELLOW}Config saved to: azure-config.env${NC}"
echo -e "${YELLOW}Next: ./scripts/create-hello-world-dashboard.sh${NC}"
