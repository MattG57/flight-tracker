#!/bin/bash

# Flight Tracker - Azure Setup Verification Script
# Verifies all required Azure resources are properly configured

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (edit these to match your setup)
RESOURCE_GROUP="${RESOURCE_GROUP:-flighttracker1}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-flighttracker1}"
STORAGE_CONTAINER="${STORAGE_CONTAINER:-flight-tracker-data}"
STATIC_WEB_APP="${STATIC_WEB_APP:-flight-tracker-dashboard}"
APP_INSIGHTS="${APP_INSIGHTS:-flight-tracker-insights}"

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}  Flight Tracker - Azure Setup Verification${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
}

print_section() {
    echo -e "${BLUE}▶ $1${NC}"
}

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++)) || true
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++)) || true
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((CHECKS_WARNING++)) || true
}

check_info() {
    echo -e "  ${NC}$1${NC}"
}

print_summary() {
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}  Summary${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Passed:${NC}   $CHECKS_PASSED"
    echo -e "${YELLOW}Warnings:${NC} $CHECKS_WARNING"
    echo -e "${RED}Failed:${NC}   $CHECKS_FAILED"
    echo ""
    
    if [ $CHECKS_FAILED -eq 0 ] && [ $CHECKS_WARNING -eq 0 ]; then
        echo -e "${GREEN}✓ All checks passed! Your Azure setup is ready.${NC}"
        exit 0
    elif [ $CHECKS_FAILED -eq 0 ]; then
        echo -e "${YELLOW}⚠ Setup is functional but has warnings to address.${NC}"
        exit 0
    else
        echo -e "${RED}✗ Setup has critical issues that need to be fixed.${NC}"
        exit 1
    fi
}

# Check if Azure CLI is installed
check_azure_cli() {
    print_section "Checking Prerequisites"
    
    if command -v az &> /dev/null; then
        AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
        check_pass "Azure CLI installed (version: $AZ_VERSION)"
    else
        check_fail "Azure CLI not installed"
        check_info "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    fi
}

# Check if logged in to Azure
check_azure_login() {
    if az account show &> /dev/null; then
        ACCOUNT_NAME=$(az account show --query "name" -o tsv)
        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
        check_pass "Logged in to Azure"
        check_info "Account: $ACCOUNT_NAME"
        check_info "Subscription: $SUBSCRIPTION_ID"
    else
        check_fail "Not logged in to Azure"
        check_info "Run: az login"
        exit 1
    fi
}

# Check Resource Group
check_resource_group() {
    print_section "Checking Resource Group"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        LOCATION=$(az group show --name "$RESOURCE_GROUP" --query "location" -o tsv)
        check_pass "Resource group '$RESOURCE_GROUP' exists"
        check_info "Location: $LOCATION"
    else
        check_fail "Resource group '$RESOURCE_GROUP' not found"
        check_info "Run: az group create --name $RESOURCE_GROUP --location eastus2"
    fi
}

# Check Storage Account
check_storage_account() {
    print_section "Checking Storage Account"
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        check_pass "Storage account '$STORAGE_ACCOUNT' exists"
        
        # Check encryption
        ENCRYPTION=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" \
            --query "encryption.services.blob.enabled" -o tsv)
        if [ "$ENCRYPTION" = "true" ]; then
            check_pass "Blob encryption enabled"
        else
            check_warn "Blob encryption not enabled"
        fi
        
        # Check HTTPS only
        HTTPS_ONLY=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" \
            --query "enableHttpsTrafficOnly" -o tsv)
        if [ "$HTTPS_ONLY" = "true" ]; then
            check_pass "HTTPS-only traffic enforced"
        else
            check_fail "HTTPS-only traffic not enforced"
        fi
        
        # Check minimum TLS version
        TLS_VERSION=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" \
            --query "minimumTlsVersion" -o tsv)
        if [ "$TLS_VERSION" = "TLS1_2" ]; then
            check_pass "Minimum TLS version is 1.2"
        else
            check_warn "Minimum TLS version is $TLS_VERSION (recommend TLS1_2)"
        fi
        
    else
        check_fail "Storage account '$STORAGE_ACCOUNT' not found"
    fi
}

# Check Storage Container
check_storage_container() {
    print_section "Checking Storage Container"
    
    if az storage container exists \
        --account-name "$STORAGE_ACCOUNT" \
        --name "$STORAGE_CONTAINER" \
        --query "exists" -o tsv 2>/dev/null | grep -q "true"; then
        check_pass "Container '$STORAGE_CONTAINER' exists"
        
        # Check public access
        PUBLIC_ACCESS=$(az storage container show \
            --account-name "$STORAGE_ACCOUNT" \
            --name "$STORAGE_CONTAINER" \
            --query "properties.publicAccess" -o tsv 2>/dev/null)
        if [ "$PUBLIC_ACCESS" = "null" ] || [ -z "$PUBLIC_ACCESS" ]; then
            check_pass "Container is private (no public access)"
        else
            check_warn "Container has public access: $PUBLIC_ACCESS"
        fi
        
        # Check if folders exist
        BLOB_COUNT=$(az storage blob list \
            --account-name "$STORAGE_ACCOUNT" \
            --container-name "$STORAGE_CONTAINER" \
            --query "length(@)" -o tsv 2>/dev/null || echo "0")
        check_info "Blob count: $BLOB_COUNT"
        
    else
        check_fail "Container '$STORAGE_CONTAINER' not found"
    fi
}

# Check Static Web App
check_static_web_app() {
    print_section "Checking Azure Static Web App"
    
    if az staticwebapp show --name "$STATIC_WEB_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        check_pass "Static Web App '$STATIC_WEB_APP' exists"
        
        # Get URL
        APP_URL=$(az staticwebapp show --name "$STATIC_WEB_APP" --resource-group "$RESOURCE_GROUP" \
            --query "defaultHostname" -o tsv)
        check_info "URL: https://$APP_URL"
        
        # Check SKU
        SKU=$(az staticwebapp show --name "$STATIC_WEB_APP" --resource-group "$RESOURCE_GROUP" \
            --query "sku.name" -o tsv)
        check_info "SKU: $SKU"
        
        # Check if connected to GitHub
        REPO_URL=$(az staticwebapp show --name "$STATIC_WEB_APP" --resource-group "$RESOURCE_GROUP" \
            --query "repositoryUrl" -o tsv 2>/dev/null)
        if [ -n "$REPO_URL" ] && [ "$REPO_URL" != "null" ]; then
            check_pass "Connected to GitHub repository"
            check_info "Repository: $REPO_URL"
        else
            check_warn "Not connected to GitHub repository"
        fi
        
    else
        check_fail "Static Web App '$STATIC_WEB_APP' not found"
    fi
}

# Check Environment Variables
check_environment_variables() {
    print_section "Checking Environment Variables"
    
    if az staticwebapp show --name "$STATIC_WEB_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        SETTINGS=$(az staticwebapp appsettings list \
            --name "$STATIC_WEB_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --query "properties" -o json 2>/dev/null)
        
        if [ -n "$SETTINGS" ] && [ "$SETTINGS" != "{}" ]; then
            # Required settings
            REQUIRED_VARS=("AZURE_STORAGE_ACCOUNT" "AZURE_STORAGE_KEY" "AZURE_STORAGE_CONTAINER" 
                          "GITHUB_CLIENT_ID" "GITHUB_CLIENT_SECRET" "JWT_SECRET")
            
            for VAR in "${REQUIRED_VARS[@]}"; do
                if echo "$SETTINGS" | jq -e ".$VAR" > /dev/null 2>&1; then
                    check_pass "Environment variable '$VAR' is set"
                else
                    check_fail "Environment variable '$VAR' is missing"
                fi
            done
            
            # Optional settings
            OPTIONAL_VARS=("AUTHORIZED_ORG" "ADMIN_TEAM" "CONTRIBUTOR_TEAM")
            for VAR in "${OPTIONAL_VARS[@]}"; do
                if echo "$SETTINGS" | jq -e ".$VAR" > /dev/null 2>&1; then
                    check_pass "Optional variable '$VAR' is set"
                else
                    check_warn "Optional variable '$VAR' not set"
                fi
            done
        else
            check_fail "No environment variables configured"
        fi
    fi
}

# Check Application Insights (optional)
check_application_insights() {
    print_section "Checking Application Insights (Optional)"
    
    if az monitor app-insights component show \
        --app "$APP_INSIGHTS" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        check_pass "Application Insights '$APP_INSIGHTS' exists"
        
        INSTRUMENTATION_KEY=$(az monitor app-insights component show \
            --app "$APP_INSIGHTS" \
            --resource-group "$RESOURCE_GROUP" \
            --query "instrumentationKey" -o tsv)
        check_info "Instrumentation key configured"
    else
        check_warn "Application Insights not configured (optional but recommended)"
        check_info "Run: az monitor app-insights component create --app $APP_INSIGHTS --location eastus2 --resource-group $RESOURCE_GROUP"
    fi
}

# Check connectivity
check_connectivity() {
    print_section "Checking Connectivity"
    
    if az staticwebapp show --name "$STATIC_WEB_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        APP_URL=$(az staticwebapp show --name "$STATIC_WEB_APP" --resource-group "$RESOURCE_GROUP" \
            --query "defaultHostname" -o tsv)
        
        if command -v curl &> /dev/null; then
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$APP_URL" --max-time 10 || echo "000")
            if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 500 ]; then
                check_pass "Dashboard is accessible (HTTP $HTTP_CODE)"
            else
                check_warn "Dashboard returned HTTP $HTTP_CODE"
            fi
        else
            check_info "curl not available, skipping connectivity test"
        fi
    fi
}

# Main execution
main() {
    print_header
    
    check_azure_cli
    check_azure_login
    check_resource_group
    check_storage_account
    check_storage_container
    check_static_web_app
    check_environment_variables
    check_application_insights
    check_connectivity
    
    print_summary
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
