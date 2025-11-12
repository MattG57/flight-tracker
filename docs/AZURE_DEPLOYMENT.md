# Azure Deployment Guide

Complete guide for deploying Flight Tracker entirely on Azure.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Azure Cloud                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  Azure Static Web Apps                              │  │
│  │  - Next.js Dashboard (Static)                       │  │
│  │  - API Routes (Azure Functions - Node.js)          │  │
│  │  - DuckDB embedded in Functions                     │  │
│  │  - Auto-scaling, HTTPS, CDN                         │  │
│  └──────────────────┬──────────────────────────────────┘  │
│                     │                                       │
│                     ▼                                       │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  Azure Blob Storage                                 │  │
│  │  - flight-tracker-data container                    │  │
│  │    - flights/*.jsonl                                │  │
│  │    - audit-logs/*.jsonl                             │  │
│  │  - AES-256 encryption at rest                       │  │
│  │  - HTTPS-only access                                │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  Azure Monitor (Optional)                           │  │
│  │  - Application Insights                             │  │
│  │  - Log Analytics                                    │  │
│  │  - Alerts & Dashboards                              │  │
│  └─────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Azure Subscription**: [Create free account](https://azure.microsoft.com/free/)
2. **Azure CLI**: [Install instructions](https://docs.microsoft.com/cli/azure/install-azure-cli)
3. **GitHub Account**: For OAuth and deployment
4. **Node.js**: v18+ for local development

## Step-by-Step Deployment

### 1. Setup Azure CLI

```bash
# Login to Azure
az login

# Set subscription (if you have multiple)
az account list --output table
az account set --subscription "Your Subscription Name"

# Create resource group
az group create \
  --name flight-tracker-rg \
  --location eastus2
```

### 2. Create Azure Blob Storage

```bash
# Create storage account
az storage account create \
  --name flighttracker \
  --resource-group flight-tracker-rg \
  --location eastus2 \
  --sku Standard_LRS \
  --kind StorageV2 \
  --encryption-services blob \
  --https-only true \
  --min-tls-version TLS1_2

# Get storage key
STORAGE_KEY=$(az storage account keys list \
  --account-name flighttracker \
  --resource-group flight-tracker-rg \
  --query "[0].value" -o tsv)

# Create container
az storage container create \
  --account-name flighttracker \
  --account-key "$STORAGE_KEY" \
  --name flight-tracker-data \
  --public-access off

# Create folders (by uploading empty files)
echo "" | az storage blob upload \
  --account-name flighttracker \
  --account-key "$STORAGE_KEY" \
  --container-name flight-tracker-data \
  --name flights/.keep \
  --data ""

echo "" | az storage blob upload \
  --account-name flighttracker \
  --account-key "$STORAGE_KEY" \
  --container-name flight-tracker-data \
  --name audit-logs/.keep \
  --data ""
```

### 3. Deploy Azure Static Web Apps

```bash
# Install Azure Static Web Apps CLI (for local testing)
npm install -g @azure/static-web-apps-cli

# Create static web app (connects to GitHub repo)
az staticwebapp create \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg \
  --location eastus2 \
  --source https://github.com/MattG57/flight-tracker \
  --branch main \
  --app-location "/packages/dashboard" \
  --output-location "out" \
  --login-with-github

# Get deployment token (for GitHub Actions)
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg \
  --query "properties.apiKey" -o tsv)

# Get app URL
APP_URL=$(az staticwebapp show \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg \
  --query "defaultHostname" -o tsv)

echo "Dashboard URL: https://$APP_URL"
```

**Note**: The `az staticwebapp create` with `--login-with-github` will:
1. Authenticate with GitHub
2. Add deployment token as GitHub secret
3. Create GitHub Action workflow automatically

### 4. Configure GitHub OAuth

```bash
# Visit: https://github.com/settings/developers
# Create new OAuth App with:
#   Name: Flight Tracker
#   Homepage URL: https://<your-app>.azurestaticapps.net
#   Callback URL: https://<your-app>.azurestaticapps.net/api/auth/callback
```

Save the `CLIENT_ID` and `CLIENT_SECRET`.

### 5. Set Environment Variables

```bash
# Generate JWT secret
JWT_SECRET=$(openssl rand -base64 32)

# Set environment variables in Azure Static Web Apps
az staticwebapp appsettings set \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg \
  --setting-names \
    AZURE_STORAGE_ACCOUNT=flighttracker \
    AZURE_STORAGE_KEY="$STORAGE_KEY" \
    AZURE_STORAGE_CONTAINER=flight-tracker-data \
    GITHUB_CLIENT_ID="<your-client-id>" \
    GITHUB_CLIENT_SECRET="<your-client-secret>" \
    JWT_SECRET="$JWT_SECRET" \
    AUTHORIZED_ORG="your-github-org" \
    ADMIN_TEAM="flight-tracker-admins" \
    CONTRIBUTOR_TEAM="flight-tracker-contributors"

# Verify
az staticwebapp appsettings list \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg
```

### 6. Deploy Code

```bash
# Push to GitHub main branch
git push origin main

# GitHub Action automatically deploys to Azure
# Check status at: https://github.com/MattG57/flight-tracker/actions
```

### 7. Configure Custom Domain (Optional)

```bash
# Add custom domain
az staticwebapp hostname set \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg \
  --hostname flights.yourdomain.com

# Configure DNS (add CNAME record):
# flights.yourdomain.com -> <your-app>.azurestaticapps.net

# SSL certificate automatically provisioned by Azure
```

## Local Development

### Setup

```bash
cd /Users/mattg57/flight-tracker/packages/dashboard

# Install dependencies
npm install

# Create .env.local
cat > .env.local << EOF
AZURE_STORAGE_ACCOUNT=flighttracker
AZURE_STORAGE_KEY=<your-key>
AZURE_STORAGE_CONTAINER=flight-tracker-data
GITHUB_CLIENT_ID=<your-client-id>
GITHUB_CLIENT_SECRET=<your-client-secret>
JWT_SECRET=<your-jwt-secret>
AUTHORIZED_ORG=your-github-org
ADMIN_TEAM=flight-tracker-admins
CONTRIBUTOR_TEAM=flight-tracker-contributors
EOF

# Run locally
npm run dev
# Dashboard: http://localhost:3000
```

### Test with Azure Static Web Apps CLI

```bash
# Build for production
npm run build

# Run with Azure SWA CLI (simulates Azure Functions)
swa start out --api-location api

# Access at: http://localhost:4280
```

## Monitoring & Observability

### Enable Application Insights

```bash
# Create Application Insights
az monitor app-insights component create \
  --app flight-tracker-insights \
  --location eastus2 \
  --resource-group flight-tracker-rg \
  --application-type web

# Get instrumentation key
INSTRUMENTATION_KEY=$(az monitor app-insights component show \
  --app flight-tracker-insights \
  --resource-group flight-tracker-rg \
  --query "instrumentationKey" -o tsv)

# Link to Static Web App
az staticwebapp appsettings set \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg \
  --setting-names \
    APPINSIGHTS_INSTRUMENTATIONKEY="$INSTRUMENTATION_KEY"
```

### View Logs

```bash
# Stream logs
az staticwebapp logs \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg \
  --follow

# Query with Log Analytics
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "requests | where timestamp > ago(1h)"
```

## Cost Estimation

### Free Tier (Sufficient for Pilot)

| Service | Free Tier | Cost Beyond Free |
|---------|-----------|------------------|
| **Azure Static Web Apps** | 100GB bandwidth/month | $0.20/GB |
| **Azure Blob Storage** | 5GB storage | $0.018/GB/month |
| **Azure Functions** | 1M executions/month | $0.20/1M executions |
| **Bandwidth** | First 100GB free | $0.087/GB |

### Estimated Monthly Cost (30k flights, 10k queries/day)

- **Storage**: 150MB × $0.018/GB = **$0.003**
- **Bandwidth**: < 100GB (free)
- **Functions**: 300k executions (free)
- **Total**: **~$0.00** (within free tier)

### When you exceed free tier (~100k flights, 100k queries/day):

- **Storage**: 500MB × $0.018/GB = **$0.01**
- **Bandwidth**: 150GB × $0.087/GB = **$13**
- **Functions**: 3M executions × $0.20/1M = **$0.60**
- **Total**: **~$14/month**

## Security Hardening

### Network Security

```bash
# Restrict storage account access to Static Web App IP
az storage account network-rule add \
  --account-name flighttracker \
  --resource-group flight-tracker-rg \
  --ip-address <static-web-app-outbound-ip>

# Enable firewall (deny all by default)
az storage account update \
  --name flighttracker \
  --resource-group flight-tracker-rg \
  --default-action Deny
```

### Enable Soft Delete (Data Recovery)

```bash
az storage blob service-properties delete-policy update \
  --account-name flighttracker \
  --enable true \
  --days-retained 30
```

### Rotate Storage Keys

```bash
# Rotate key (automatically invalidates old SAS tokens)
az storage account keys renew \
  --account-name flighttracker \
  --resource-group flight-tracker-rg \
  --key primary

# Update environment variable with new key
STORAGE_KEY=$(az storage account keys list \
  --account-name flighttracker \
  --resource-group flight-tracker-rg \
  --query "[0].value" -o tsv)

az staticwebapp appsettings set \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg \
  --setting-names AZURE_STORAGE_KEY="$STORAGE_KEY"
```

## Troubleshooting

### Dashboard not loading

```bash
# Check deployment status
az staticwebapp show \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg

# View build logs
az staticwebapp show \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg \
  --query "buildProperties"
```

### API routes returning errors

```bash
# Check Function logs in Application Insights
az monitor app-insights query \
  --app flight-tracker-insights \
  --resource-group flight-tracker-rg \
  --analytics-query "traces | where timestamp > ago(1h) | order by timestamp desc"
```

### Storage access denied

```bash
# Verify storage key
az storage account keys list \
  --account-name flighttracker \
  --resource-group flight-tracker-rg

# Test access
az storage blob list \
  --account-name flighttracker \
  --container-name flight-tracker-data \
  --account-key "$STORAGE_KEY"
```

## Cleanup (Delete Everything)

```bash
# Delete entire resource group (removes all resources)
az group delete \
  --name flight-tracker-rg \
  --yes --no-wait

# Remove GitHub OAuth app manually at:
# https://github.com/settings/developers
```

## Production Checklist

- [ ] Azure Blob Storage created with encryption
- [ ] Azure Static Web Apps deployed
- [ ] GitHub OAuth app configured
- [ ] Environment variables set in Azure
- [ ] Custom domain configured (optional)
- [ ] Application Insights enabled
- [ ] Storage key rotation scheduled
- [ ] Backup strategy defined
- [ ] Monitoring alerts configured
- [ ] Security review completed

## Next Steps

1. Deploy core package with Flight schema
2. Build dashboard UI (packages/dashboard)
3. Implement agent-hooks for data capture
4. Set up CI/CD pipeline
5. Configure monitoring and alerts

## Resources

- [Azure Static Web Apps Documentation](https://docs.microsoft.com/azure/static-web-apps/)
- [Azure Blob Storage Documentation](https://docs.microsoft.com/azure/storage/blobs/)
- [DuckDB Azure Integration](https://duckdb.org/docs/guides/import/azure)
- [Next.js Deployment to Azure](https://nextjs.org/docs/deployment)
