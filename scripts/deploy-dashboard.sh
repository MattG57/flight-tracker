#!/bin/bash
# Flight Tracker - Deploy Dashboard to Azure Static Web App
# Creates Azure Static Web App and deploys the dashboard

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Flight Tracker - Dashboard Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI not found${NC}"
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo -e "${YELLOW}Warning: GitHub CLI not found (optional for GitHub integration)${NC}"
fi

if [ ! -f azure-config.env ]; then
    echo -e "${RED}Error: azure-config.env not found. Run ./scripts/setup-azure.sh first${NC}"
    exit 1
fi

if [ ! -d packages/dashboard ]; then
    echo -e "${RED}Error: Dashboard not created. Run ./scripts/create-hello-world-dashboard.sh first${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites met${NC}"
echo

# Load configuration
source azure-config.env

# Configuration
STATIC_WEB_APP="${STATIC_WEB_APP:-flight-tracker-dashboard}"
LOCATION="${LOCATION:-eastus2}"
SKU="${SKU:-Free}"
REPO_URL="https://github.com/MattG57/flight-tracker.git"
BRANCH="${BRANCH:-main}"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Static Web App: $STATIC_WEB_APP"
echo "  Location: $LOCATION"
echo "  SKU: $SKU"
echo "  Repository: $REPO_URL"
echo "  Branch: $BRANCH"
echo

# Check if logged in to Azure
echo -e "${YELLOW}Checking Azure login...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Please login to Azure...${NC}"
    az login
fi

SUBSCRIPTION=$(az account show --query "name" -o tsv)
echo -e "${GREEN}✓ Logged in to subscription: $SUBSCRIPTION${NC}"
echo

# Check if Static Web App already exists
echo -e "${YELLOW}Checking if Static Web App exists...${NC}"
if az staticwebapp show --name "$STATIC_WEB_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    echo -e "${YELLOW}Static Web App '$STATIC_WEB_APP' already exists${NC}"
    echo -e "${YELLOW}Do you want to update it? (y/N)${NC}"
    read -r RESPONSE
    if [[ ! "$RESPONSE" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Skipping Static Web App creation${NC}"
        SKIP_CREATE=true
    fi
fi

# Create Static Web App
if [ "$SKIP_CREATE" != "true" ]; then
    echo -e "${YELLOW}Creating Azure Static Web App...${NC}"
    
    # Create without GitHub integration first (manual deployment)
    az staticwebapp create \
        --name "$STATIC_WEB_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku "$SKU" \
        --output none 2>/dev/null || {
            echo -e "${YELLOW}Note: Static Web App may already exist or require different parameters${NC}"
        }
    
    echo -e "${GREEN}✓ Static Web App created/verified${NC}"
    echo
fi

# Get the deployment token
echo -e "${YELLOW}Retrieving deployment token...${NC}"
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
    --name "$STATIC_WEB_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --query "properties.apiKey" -o tsv 2>/dev/null)

if [ -z "$DEPLOYMENT_TOKEN" ]; then
    echo -e "${RED}Error: Could not retrieve deployment token${NC}"
    echo -e "${YELLOW}You may need to configure GitHub integration manually${NC}"
else
    echo -e "${GREEN}✓ Deployment token retrieved${NC}"
fi
echo

# Configure environment variables
echo -e "${YELLOW}Configuring environment variables...${NC}"

# Apply settings
az staticwebapp appsettings set \
    --name "$STATIC_WEB_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --setting-names \
        AZURE_STORAGE_ACCOUNT="$AZURE_STORAGE_ACCOUNT" \
        AZURE_STORAGE_KEY="$AZURE_STORAGE_KEY" \
        AZURE_STORAGE_CONTAINER="$AZURE_STORAGE_CONTAINER" \
        JWT_SECRET="$JWT_SECRET" \
    --output none

echo -e "${GREEN}✓ Environment variables configured${NC}"
echo

# Get the Static Web App URL
APP_URL=$(az staticwebapp show \
    --name "$STATIC_WEB_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --query "defaultHostname" -o tsv)

# Build and deploy the dashboard
echo -e "${YELLOW}Building dashboard...${NC}"
cd packages/dashboard
npm install --silent
npm run build

echo -e "${GREEN}✓ Dashboard built${NC}"
echo

# Deploy using SWA CLI
echo -e "${YELLOW}Deploying to Azure Static Web Apps...${NC}"
swa deploy out \
    --deployment-token "$DEPLOYMENT_TOKEN" \
    --env production \
    --api-location api \
    --api-language node \
    --api-version 18

cd ../..

echo -e "${GREEN}✓ Dashboard deployed${NC}"
echo

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${YELLOW}Static Web App URL:${NC}"
echo -e "${BLUE}  https://$APP_URL${NC}"
echo
echo -e "${YELLOW}Your dashboard is now live!${NC}"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "  • Visit the URL above to see your dashboard"
echo "  • Update content in packages/dashboard"
echo "  • Re-run this script to deploy updates"
echo
echo -e "${YELLOW}For GitHub Actions deployment:${NC}"
echo "  gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN --body \"$DEPLOYMENT_TOKEN\""
echo
echo -e "${GREEN}Configuration saved to azure-config.env${NC}"

# Save deployment info to config
cat >> azure-config.env << EOF
STATIC_WEB_APP=$STATIC_WEB_APP
DEPLOYMENT_TOKEN=$DEPLOYMENT_TOKEN
APP_URL=$APP_URL
EOF

echo -e "${GREEN}✓ Deployment complete${NC}"
