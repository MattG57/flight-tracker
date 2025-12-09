# Flight Tracker

AI Agent Flight Tracking System - Monitor and analyze AI agent execution outcomes with detailed telemetry.

## Overview

Flight Tracker uses an aviation metaphor to track AI agent executions ("flights") from takeoff to landing, measuring success rates, costs, and outcomes.

## Architecture

This is a monorepo containing three main packages:

### Packages

- **`packages/core`** - Core data models, types, and storage layer
  - Flight plan schema
  - Flight Data Recorder (FDR) logs
  - Database abstraction
  
- **`packages/agent-hooks`** - Integration hooks for AI agent execution
  - Required flight plan enforcement
  - Implicit flight plan inference
  - Execution telemetry capture
  
- **`packages/dashboard`** - Analytics dashboard and visualization
  - Flight trends and metrics
  - Success/failure analysis
  - Semantic analysis of outcomes

## Getting Started

### Installation

```bash
# Install dependencies
npm install

# Run development mode
npm run dev

# Build all packages
npm run build
```

### Azure Setup & Management

Flight Tracker includes management scripts for Azure deployment and configuration:

```bash
# Setup Azure resources
./scripts/setup-azure.sh

# Verify Azure setup is correct
./scripts/verify-azure-setup.sh

# Deploy dashboard to Azure
./scripts/deploy-dashboard.sh
```

See [scripts/README-verify.md](scripts/README-verify.md) for detailed verification documentation.

## Iteration 1 Goals

- [x] Establish repo structure
- [x] Define flight data structure
- [ ] Integrate with agent execution
- [ ] Build rudimentary dashboard

## Technology Stack

- **Dashboard**: Next.js on Azure Static Web Apps
- **API**: Azure Functions (Node.js)
- **Query Engine**: DuckDB (embedded analytics)
- **Storage**: Azure Blob Storage (JSONL format)
- **Auth**: GitHub OAuth + JWT
- **Cost**: Free tier for pilot (~$0/month for 30k flights)

See [docs/DATA_STORAGE.md](docs/DATA_STORAGE.md) for details.

## Deployment

Fully deployed on Azure:
- Azure Static Web Apps (dashboard + API)
- Azure Blob Storage (data)
- GitHub Actions (CI/CD)

See [docs/AZURE_DEPLOYMENT.md](docs/AZURE_DEPLOYMENT.md) for complete deployment guide.

### Management Scripts

The `scripts/` directory contains utilities for managing Azure resources:

| Script | Purpose |
|--------|---------|
| `setup-azure.sh` | Initialize Azure resources (resource group, storage, static web app) |
| `verify-azure-setup.sh` | Comprehensive verification of Azure configuration |
| `deploy-dashboard.sh` | Deploy dashboard to Azure Static Web Apps |
| `enable-managed-identity.sh` | Enable Azure Managed Identity for storage access |
| `toggle-auth-method.sh` | Switch between Shared Key and Azure AD authentication |
| `toggle-shared-key.sh` | Enable/disable shared key access for storage |
| `create-hello-world-dashboard.sh` | Create a test dashboard deployment |

Run `./scripts/verify-azure-setup.sh` after deployment to ensure everything is configured correctly.

## Security

Flight Tracker implements comprehensive security measures:

### Authentication & Authorization
- **Authentication**: GitHub OAuth
- **Authorization**: JWT + role-based access control (RBAC)
- **Session Management**: Secure token-based sessions

### Storage Security
- **Encryption**: Azure Blob Storage encryption at rest (AES-256)
- **Transport**: HTTPS/TLS for all data in transit
- **Access Methods**: 
  - Shared Key authentication (default)
  - Azure AD/Managed Identity (recommended for production)
  - Time-limited SAS tokens for user access
- **Row-Level Security**: DuckDB filtering by user/team/org

### Management Tools
Use the authentication management scripts to configure storage access:
- `./scripts/toggle-auth-method.sh` - Switch authentication methods
- `./scripts/enable-managed-identity.sh` - Enable Managed Identity
- `./scripts/toggle-shared-key.sh` - Control shared key access

See [docs/SECURITY.md](docs/SECURITY.md) for complete security architecture.
