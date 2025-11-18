# Azure Setup Verification

This script verifies that all required Azure resources for Flight Tracker are properly configured.

## Usage

### Basic Usage

```bash
./scripts/verify-azure-setup.sh
```

### Custom Resource Names

If you used different names for your Azure resources:

```bash
RESOURCE_GROUP=my-rg \
STORAGE_ACCOUNT=mystorageaccount \
STORAGE_CONTAINER=my-container \
STATIC_WEB_APP=my-web-app \
APP_INSIGHTS=my-insights \
./scripts/verify-azure-setup.sh
```

## What It Checks

### Prerequisites
- ✓ Azure CLI installed and version
- ✓ Logged in to Azure account

### Resource Group
- ✓ Resource group exists
- ✓ Location information

### Storage Account
- ✓ Storage account exists
- ✓ Blob encryption enabled
- ✓ HTTPS-only traffic enforced
- ✓ Minimum TLS version (1.2 recommended)

### Storage Container
- ✓ Container exists and is private
- ✓ No public access configured
- ✓ Blob count

### Azure Static Web App
- ✓ Static Web App exists
- ✓ Dashboard URL
- ✓ SKU tier
- ✓ GitHub repository connection

### Environment Variables
- ✓ Required variables set:
  - `AZURE_STORAGE_ACCOUNT`
  - `AZURE_STORAGE_KEY`
  - `AZURE_STORAGE_CONTAINER`
  - `GITHUB_CLIENT_ID`
  - `GITHUB_CLIENT_SECRET`
  - `JWT_SECRET`
- ⚠ Optional variables:
  - `AUTHORIZED_ORG`
  - `ADMIN_TEAM`
  - `CONTRIBUTOR_TEAM`

### Application Insights (Optional)
- ⚠ Application Insights configured
- ⚠ Instrumentation key set

### Connectivity
- ✓ Dashboard is accessible via HTTPS

## Output

The script uses color-coded output:
- 🟢 **Green (✓)**: Check passed
- 🟡 **Yellow (⚠)**: Warning - non-critical issue
- 🔴 **Red (✗)**: Failed - needs attention

## Exit Codes

- `0`: All checks passed or only warnings
- `1`: Critical failures detected

## Example Output

```
================================================
  Flight Tracker - Azure Setup Verification
================================================

▶ Checking Prerequisites
✓ Azure CLI installed (version: 2.50.0)
✓ Logged in to Azure
  Account: My Subscription
  Subscription: abc-123-def-456

▶ Checking Resource Group
✓ Resource group 'flight-tracker-rg' exists
  Location: eastus2

▶ Checking Storage Account
✓ Storage account 'flighttracker' exists
✓ Blob encryption enabled
✓ HTTPS-only traffic enforced
✓ Minimum TLS version is 1.2

▶ Checking Storage Container
✓ Container 'flight-tracker-data' exists
✓ Container is private (no public access)
  Blob count: 5

▶ Checking Azure Static Web App
✓ Static Web App 'flight-tracker-dashboard' exists
  URL: https://flight-tracker-dashboard.azurestaticapps.net
  SKU: Free
✓ Connected to GitHub repository
  Repository: https://github.com/MattG57/flight-tracker

▶ Checking Environment Variables
✓ Environment variable 'AZURE_STORAGE_ACCOUNT' is set
✓ Environment variable 'AZURE_STORAGE_KEY' is set
✓ Environment variable 'AZURE_STORAGE_CONTAINER' is set
✓ Environment variable 'GITHUB_CLIENT_ID' is set
✓ Environment variable 'GITHUB_CLIENT_SECRET' is set
✓ Environment variable 'JWT_SECRET' is set
✓ Optional variable 'AUTHORIZED_ORG' is set

▶ Checking Application Insights (Optional)
⚠ Application Insights not configured (optional but recommended)

▶ Checking Connectivity
✓ Dashboard is accessible (HTTP 200)

================================================
  Summary
================================================
Passed:   22
Warnings: 1
Failed:   0

✓ All checks passed! Your Azure setup is ready.
```

## Troubleshooting

### Not logged in to Azure
```bash
az login
```

### Resource group not found
```bash
az group create --name flight-tracker-rg --location eastus2
```

### Storage account issues
Check the deployment guide: `docs/AZURE_DEPLOYMENT.md`

### Environment variables missing
```bash
az staticwebapp appsettings set \
  --name flight-tracker-dashboard \
  --resource-group flight-tracker-rg \
  --setting-names KEY=value
```

## Related Documentation

- [Azure Deployment Guide](../docs/AZURE_DEPLOYMENT.md)
- [Azure Static Web Apps Docs](https://docs.microsoft.com/azure/static-web-apps/)
- [Azure Blob Storage Docs](https://docs.microsoft.com/azure/storage/blobs/)
