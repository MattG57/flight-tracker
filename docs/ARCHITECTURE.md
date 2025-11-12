# Architecture

## Data Lifecycle Strategy

### Architecture: DuckDB + Cloud Storage

Flight Tracker uses **DuckDB** (embedded analytics engine) with **Azure Blob Storage** for scalable, cost-effective data storage.

**Key Benefits:**
- **No database server** - DuckDB is embedded, queries cloud storage directly
- **Cost effective** - ~$0.10/month for 30k flights (storage + reads)
- **Serverless** - No infrastructure to manage
- **Fast analytics** - Columnar storage, parallel processing
- **Multi-user support** - GitHub OAuth + JWT + row-level security

### Data Flow

```
Agent Execution
      ↓
agent-hooks (capture telemetry)
      ↓
core (append JSONL to Azure Blob)
      ↓
DuckDB (query Azure Blob directly)
      ↓
dashboard (visualize)
```

### Storage Format

**JSONL** (JSON Lines) in Azure Blob Storage:
```
azure://flight-tracker-data/
├── flights/
│   └── 2024/11/12/flights.jsonl
└── users/
    └── access-log.jsonl
```

### Multi-User Security

**Authentication**: GitHub OAuth
**Authorization**: JWT tokens with role-based access
**Encryption**: Azure Blob encryption at rest (AES-256)
**Access Control**: Time-limited SAS tokens per user

See [DATA_STORAGE.md](./DATA_STORAGE.md) for detailed security architecture.

## Component Communication

```
Agent Execution
      ↓
agent-hooks (capture telemetry)
      ↓
core (write to SQLite)
      ↓
dashboard (query and visualize)
```

## Technology Stack

**Selected:**
- **Query Engine**: DuckDB (embedded analytics, queries cloud storage)
- **Storage**: Azure Blob Storage (JSONL format)
- **Dashboard Framework**: Next.js (React + API routes)
- **Authentication**: GitHub OAuth
- **Authorization**: JWT + Row-Level Security
- **Hosting**: Azure Static Web Apps (dashboard + API) + Azure Blob Storage (data)

**To Be Decided:**
- **Charts**: Recharts vs. Chart.js vs. D3
- **UI**: shadcn/ui vs. MUI vs. custom

## Next Steps

1. Define Flight data schema in `packages/core`
2. Implement GitHub OAuth flow
3. Setup Azure Blob Storage + DuckDB integration
4. Build dashboard with authentication
