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

## Data Storage

Currently using SQLite for simplicity during pilot phase. Can migrate to PostgreSQL later if needed.

## Dashboard Hosting

Local-first approach for pilot. Dashboard runs on localhost and reads from shared data store.
