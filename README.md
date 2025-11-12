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

```bash
# Install dependencies
npm install

# Run development mode
npm run dev

# Build all packages
npm run build
```

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

## Security

- **Authentication**: GitHub OAuth
- **Authorization**: JWT + role-based access control
- **Encryption**: Azure Blob (at rest) + HTTPS (in transit)
- **Row-Level Security**: DuckDB filtering by user/team/org

See [docs/SECURITY.md](docs/SECURITY.md) for security architecture.
