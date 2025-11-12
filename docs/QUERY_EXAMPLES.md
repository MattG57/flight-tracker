# DuckDB Query Examples

This document demonstrates how DuckDB + Azure Blob Storage supports the Flight Tracker query and security requirements.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     User (Browser)                          │
│  - Authenticated via GitHub OAuth                           │
│  - Has JWT token with permissions                           │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTPS
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Dashboard (Next.js on Vercel)                  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  API Route: /api/flights/query                       │  │
│  │  1. Validate JWT                                     │  │
│  │  2. Get user permissions (from GitHub teams)        │  │
│  │  3. Generate time-limited SAS token (1 hour)        │  │
│  │  4. Build DuckDB query with RLS filters             │  │
│  │  5. Execute query                                    │  │
│  │  6. Log access (audit)                               │  │
│  │  7. Return filtered data                             │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  DuckDB (Embedded in Node.js)                        │  │
│  │  - Queries Azure Blob directly                       │  │
│  │  - No data staging required                          │  │
│  │  - Columnar execution (fast analytics)               │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTPS + SAS Token
                     ▼
┌─────────────────────────────────────────────────────────────┐
│         Azure Blob Storage (Encrypted at Rest)              │
│                                                              │
│  flight-tracker-data/                                       │
│  ├── flights/                                               │
│  │   ├── 2025/01/15/flights.jsonl                          │
│  │   ├── 2025/01/16/flights.jsonl                          │
│  │   └── 2025/01/17/flights.jsonl                          │
│  └── audit-logs/                                            │
│      └── 2025-01-17.jsonl                                   │
└─────────────────────────────────────────────────────────────┘
```

## Basic Query Requirements

### 1. List All Flights (with RLS)

**Dashboard Question:** "Show me my flights"

```typescript
// API Route: /api/flights/list
export default requirePermission('canReadFlights')(async (req, res) => {
  const { user, permissions } = req;
  
  // Generate SAS token with read-only permission
  const sasToken = generateSASToken(user, permissions, 60); // 1 hour
  
  // Build query with Row-Level Security
  let whereClause = 'WHERE 1=1';
  
  switch (permissions.scope) {
    case 'own':
      whereClause += ` AND "pilot"->>'githubLogin' = '${user.login}'`;
      break;
    case 'team':
      const teamMembers = await getTeamMembers(user.teams);
      whereClause += ` AND "pilot"->>'githubLogin' IN (${teamMembers.map(m => `'${m}'`).join(',')})`;
      break;
    case 'org':
      whereClause += ` AND metadata->>'orgId' = '${user.orgs[0]}'`;
      break;
    case 'all':
      // Admin - no additional filter
      break;
  }
  
  const db = await DuckDB.create();
  const result = await db.query(`
    SELECT 
      flightId,
      "pilot"->>'githubLogin' as pilot,
      status,
      "goal"->>'destination' as destination,
      "goal"->>'description' as description,
      createdAt,
      "executionLog"->'duration'->>'totalMinutes' as durationMinutes,
      "executionLog"->'cost'->'copilot'->>'estimatedCost' as cost
    FROM read_json('azure://flight-tracker-data/flights/**/*.jsonl?${sasToken}')
    ${whereClause}
    ORDER BY createdAt DESC
    LIMIT 100
  `);
  
  await logAccess(req, 'read', 'flights', { rowCount: result.length });
  
  res.json(result);
});
```

**Key Points:**
- ✅ **No data copying** - DuckDB reads directly from Azure Blob
- ✅ **Row-Level Security** - WHERE clause filters by user scope
- ✅ **Time-limited access** - SAS token expires in 1 hour
- ✅ **Audit logging** - Every query is logged
- ✅ **JSON path queries** - DuckDB extracts nested fields efficiently

### 2. Filter by Status

**Dashboard Question:** "Show me all successful flights"

```typescript
// API Route: /api/flights/query
export default requirePermission('canReadFlights')(async (req, res) => {
  const { user, permissions } = req;
  const { status } = req.query; // e.g., "successful"
  
  const sasToken = generateSASToken(user, permissions, 60);
  
  let whereClause = buildRLSFilter(user, permissions);
  
  if (status) {
    whereClause += ` AND status = '${status}'`;
  }
  
  const db = await DuckDB.create();
  const result = await db.query(`
    SELECT *
    FROM read_json('azure://flight-tracker-data/flights/**/*.jsonl?${sasToken}')
    ${whereClause}
    ORDER BY createdAt DESC
  `);
  
  res.json(result);
});
```

### 3. Count Flights by Destination (Trend Analysis)

**Dashboard Question:** "What destinations are popular?"

```typescript
// API Route: /api/analytics/destinations
export default requirePermission('canReadFlights')(async (req, res) => {
  const { user, permissions } = req;
  const sasToken = generateSASToken(user, permissions, 60);
  
  const whereClause = buildRLSFilter(user, permissions);
  
  const db = await DuckDB.create();
  const result = await db.query(`
    SELECT 
      "goal"->>'destination' as destination,
      COUNT(*) as flightCount,
      AVG(("executionLog"->'duration'->>'totalMinutes')::FLOAT) as avgDuration,
      SUM(CASE WHEN status = 'successful' THEN 1 ELSE 0 END) as successCount,
      SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) as failureCount
    FROM read_json('azure://flight-tracker-data/flights/**/*.jsonl?${sasToken}')
    ${whereClause}
    GROUP BY "goal"->>'destination'
    ORDER BY flightCount DESC
  `);
  
  res.json(result);
});
```

**Output:**
```json
[
  {
    "destination": "bug-fix",
    "flightCount": 45,
    "avgDuration": 52.3,
    "successCount": 42,
    "failureCount": 3
  },
  {
    "destination": "feature",
    "flightCount": 23,
    "avgDuration": 180.5,
    "successCount": 18,
    "failureCount": 5
  }
]
```

### 4. Success Rate Over Time

**Dashboard Question:** "Is progress/learning happening?"

```typescript
// API Route: /api/analytics/success-rate
export default requirePermission('canReadFlights')(async (req, res) => {
  const { user, permissions } = req;
  const { startDate, endDate } = req.query;
  
  const sasToken = generateSASToken(user, permissions, 60);
  let whereClause = buildRLSFilter(user, permissions);
  
  if (startDate) {
    whereClause += ` AND createdAt >= '${startDate}'`;
  }
  if (endDate) {
    whereClause += ` AND createdAt <= '${endDate}'`;
  }
  
  const db = await DuckDB.create();
  const result = await db.query(`
    SELECT 
      DATE_TRUNC('day', CAST(createdAt AS TIMESTAMP)) as date,
      COUNT(*) as totalFlights,
      SUM(CASE WHEN status = 'successful' THEN 1 ELSE 0 END) as successfulFlights,
      SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) as failedFlights,
      ROUND(100.0 * SUM(CASE WHEN status = 'successful' THEN 1 ELSE 0 END) / COUNT(*), 2) as successRate
    FROM read_json('azure://flight-tracker-data/flights/**/*.jsonl?${sasToken}')
    ${whereClause}
    GROUP BY DATE_TRUNC('day', CAST(createdAt AS TIMESTAMP))
    ORDER BY date ASC
  `);
  
  res.json(result);
});
```

### 5. Failure Pareto Analysis

**Dashboard Question:** "Why are failures happening?"

```typescript
// API Route: /api/analytics/failure-pareto
export default requirePermission('canReadFlights')(async (req, res) => {
  const { user, permissions } = req;
  const sasToken = generateSASToken(user, permissions, 60);
  
  let whereClause = buildRLSFilter(user, permissions);
  whereClause += ` AND status = 'failure'`;
  
  const db = await DuckDB.create();
  const result = await db.query(`
    SELECT 
      "statusDetails"->>'failureCategory' as category,
      COUNT(*) as count,
      ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as percentage,
      SUM(COUNT(*)) OVER(ORDER BY COUNT(*) DESC) as cumulative
    FROM read_json('azure://flight-tracker-data/flights/**/*.jsonl?${sasToken}')
    ${whereClause}
    GROUP BY "statusDetails"->>'failureCategory'
    ORDER BY count DESC
  `);
  
  res.json(result);
});
```

**Output:**
```json
[
  {
    "category": "deployment_failure",
    "count": 12,
    "percentage": 40.0,
    "cumulative": 12
  },
  {
    "category": "test_failure",
    "count": 8,
    "percentage": 26.67,
    "cumulative": 20
  },
  {
    "category": "build_failure",
    "count": 6,
    "percentage": 20.0,
    "cumulative": 26
  }
]
```

### 6. International Flight Tracking

**Dashboard Question:** "Are international flights landing successfully?"

```typescript
// API Route: /api/analytics/international-flights
export default requirePermission('canReadFlights')(async (req, res) => {
  const { user, permissions } = req;
  const sasToken = generateSASToken(user, permissions, 60);
  
  let whereClause = buildRLSFilter(user, permissions);
  whereClause += ` AND ("goal"->>'isInternational')::BOOLEAN = true`;
  
  const db = await DuckDB.create();
  const result = await db.query(`
    SELECT 
      COUNT(*) as totalInternational,
      SUM(CASE WHEN status = 'successful' THEN 1 ELSE 0 END) as successfulCount,
      SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) as failedCount,
      AVG(("executionLog"->'duration'->>'totalMinutes')::FLOAT) as avgDuration,
      AVG(("executionLog"->>'reworkCount')::INT) as avgRework
    FROM read_json('azure://flight-tracker-data/flights/**/*.jsonl?${sasToken}')
    ${whereClause}
  `);
  
  res.json(result);
});
```

## Security Requirements

### 1. Authentication: GitHub OAuth

```typescript
// pages/api/auth/login.ts
export default async function handler(req, res) {
  // Redirect to GitHub OAuth
  const params = new URLSearchParams({
    client_id: process.env.GITHUB_CLIENT_ID,
    redirect_uri: `${process.env.APP_URL}/api/auth/callback`,
    scope: 'read:user read:org'
  });
  
  res.redirect(`https://github.com/login/oauth/authorize?${params}`);
}

// pages/api/auth/callback.ts
export default async function handler(req, res) {
  const { code } = req.query;
  
  // Exchange code for token
  const tokenRes = await fetch('https://github.com/login/oauth/access_token', {
    method: 'POST',
    headers: { 'Accept': 'application/json' },
    body: JSON.stringify({
      client_id: process.env.GITHUB_CLIENT_ID,
      client_secret: process.env.GITHUB_CLIENT_SECRET,
      code
    })
  });
  
  const { access_token } = await tokenRes.json();
  
  // Get user info
  const userRes = await fetch('https://api.github.com/user', {
    headers: { 'Authorization': `Bearer ${access_token}` }
  });
  const user = await userRes.json();
  
  // Get org memberships
  const orgsRes = await fetch('https://api.github.com/user/orgs', {
    headers: { 'Authorization': `Bearer ${access_token}` }
  });
  const orgs = await orgsRes.json();
  
  // Check if user is authorized (member of required org)
  const isAuthorized = orgs.some(org => org.login === process.env.AUTHORIZED_ORG);
  
  if (!isAuthorized) {
    return res.status(403).json({ error: 'Not a member of authorized organization' });
  }
  
  // Get team memberships to determine permissions
  const teamsRes = await fetch(`https://api.github.com/user/teams`, {
    headers: { 'Authorization': `Bearer ${access_token}` }
  });
  const teams = await teamsRes.json();
  
  // Issue JWT with claims
  const jwt = sign({
    sub: user.id,
    login: user.login,
    name: user.name,
    orgs: orgs.map(o => o.login),
    teams: teams.map(t => t.slug),
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours
  }, process.env.JWT_SECRET);
  
  // Set secure cookie
  res.setHeader('Set-Cookie', 
    `token=${jwt}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=86400`
  );
  
  res.redirect('/dashboard');
}
```

**Security Properties:**
- ✅ No passwords stored
- ✅ Leverages GitHub's 2FA/security
- ✅ Org membership verified
- ✅ JWT expires after 24 hours
- ✅ HttpOnly cookie prevents XSS

### 2. Authorization: Permission Levels

```typescript
// lib/permissions.ts
export async function getPermissions(user: JWTPayload): Promise<Permissions> {
  const teams = user.teams || [];
  
  // Check team membership for roles
  const isAdmin = teams.includes('flight-tracker-admins');
  const isContributor = teams.includes('flight-tracker-contributors');
  
  if (isAdmin) {
    return {
      role: 'admin',
      scope: 'all',
      canReadFlights: true,
      canWriteFlights: true,
      canDeleteFlights: true,
      canManageUsers: true
    };
  }
  
  if (isContributor) {
    return {
      role: 'contributor',
      scope: 'team',
      canReadFlights: true,
      canWriteFlights: true,
      canDeleteFlights: false,
      canManageUsers: false
    };
  }
  
  // Default: viewer with own scope
  return {
    role: 'viewer',
    scope: 'own',
    canReadFlights: true,
    canWriteFlights: false,
    canDeleteFlights: false,
    canManageUsers: false
  };
}

// Helper: Build RLS filter based on permissions
export function buildRLSFilter(user: JWTPayload, permissions: Permissions): string {
  let filter = 'WHERE 1=1';
  
  switch (permissions.scope) {
    case 'own':
      filter += ` AND "pilot"->>'githubLogin' = '${user.login}'`;
      break;
    case 'team':
      // Assuming metadata contains teamId
      filter += ` AND metadata->>'teamId' IN (${user.teams.map(t => `'${t}'`).join(',')})`;
      break;
    case 'org':
      filter += ` AND metadata->>'orgId' = '${user.orgs[0]}'`;
      break;
    case 'all':
      // Admin sees everything
      break;
  }
  
  return filter;
}
```

**Authorization Levels:**

| Role | Scope | Read | Write | Delete | See Others' Flights |
|------|-------|------|-------|--------|---------------------|
| Viewer | Own | ✅ | ❌ | ❌ | Only own |
| Contributor | Team | ✅ | ✅ | ❌ | Team members |
| Admin | All | ✅ | ✅ | ✅ | Everyone |

### 3. Encryption: At Rest & In Transit

**At Rest (Azure Blob):**
```typescript
// Azure automatically encrypts all blob storage with AES-256
// Enable via Azure CLI:
az storage account create \
  --name flighttracker \
  --resource-group flight-tracker-rg \
  --encryption-services blob \
  --https-only true

// For customer-managed keys (optional):
az storage account update \
  --name flighttracker \
  --encryption-key-source Microsoft.Keyvault \
  --encryption-key-vault https://your-vault.vault.azure.net \
  --encryption-key-name flight-tracker-key
```

**In Transit (HTTPS/TLS):**
```typescript
// next.config.js - Enforce HTTPS
module.exports = {
  async headers() {
    return [{
      source: '/:path*',
      headers: [
        {
          key: 'Strict-Transport-Security',
          value: 'max-age=63072000; includeSubDomains; preload'
        },
        {
          key: 'X-Content-Type-Options',
          value: 'nosniff'
        },
        {
          key: 'X-Frame-Options',
          value: 'DENY'
        }
      ]
    }];
  }
};
```

### 4. Access Control: Time-Limited SAS Tokens

```typescript
import { generateBlobSASQueryParameters, BlobSASPermissions, StorageSharedKeyCredential } from '@azure/storage-blob';

export function generateSASToken(
  user: JWTPayload,
  permissions: Permissions,
  durationMinutes: number = 60
): string {
  // Map permissions to SAS permissions
  const sasPermissions = new BlobSASPermissions();
  sasPermissions.read = permissions.canReadFlights;
  sasPermissions.write = permissions.canWriteFlights;
  sasPermissions.delete = permissions.canDeleteFlights;
  
  const credential = new StorageSharedKeyCredential(
    process.env.AZURE_STORAGE_ACCOUNT,
    process.env.AZURE_STORAGE_KEY
  );
  
  const startsOn = new Date();
  const expiresOn = new Date(Date.now() + durationMinutes * 60 * 1000);
  
  return generateBlobSASQueryParameters({
    containerName: 'flight-tracker-data',
    permissions: sasPermissions,
    startsOn,
    expiresOn,
    protocol: 'https' // HTTPS only
  }, credential).toString();
}
```

**SAS Token Properties:**
- ✅ Time-limited (default 1 hour)
- ✅ Permission-scoped (read/write/delete)
- ✅ HTTPS-only
- ✅ No direct storage key exposure
- ✅ Revocable (rotate storage keys)

### 5. Row-Level Security: DuckDB Filtering

**Example: User sees only their flights**

```typescript
// User: 'alice' (viewer role, 'own' scope)
const whereClause = buildRLSFilter(
  { login: 'alice' },
  { scope: 'own' }
);
// Result: WHERE 1=1 AND "pilot"->>'githubLogin' = 'alice'

const query = `
  SELECT * FROM read_json('azure://...')
  WHERE "pilot"->>'githubLogin' = 'alice'
`;
```

**Example: Team member sees team flights**

```typescript
// User: 'bob' (contributor role, 'team' scope, teams: ['engineering', 'platform'])
const whereClause = buildRLSFilter(
  { login: 'bob', teams: ['engineering', 'platform'] },
  { scope: 'team' }
);
// Result: WHERE 1=1 AND metadata->>'teamId' IN ('engineering','platform')

const query = `
  SELECT * FROM read_json('azure://...')
  WHERE metadata->>'teamId' IN ('engineering','platform')
`;
```

**Example: Admin sees everything**

```typescript
// User: 'admin' (admin role, 'all' scope)
const whereClause = buildRLSFilter(
  { login: 'admin' },
  { scope: 'all' }
);
// Result: WHERE 1=1 (no additional filter)

const query = `
  SELECT * FROM read_json('azure://...')
  WHERE 1=1
`;
```

### 6. Audit Logging

```typescript
interface AuditLog {
  timestamp: string;
  userId: string;
  userLogin: string;
  action: 'read' | 'write' | 'delete';
  resource: string;
  query: string;
  rowCount: number;
  ipAddress: string;
  userAgent: string;
  success: boolean;
  error?: string;
}

async function logAccess(
  req: NextApiRequest,
  action: string,
  resource: string,
  metadata: any
) {
  const log: AuditLog = {
    timestamp: new Date().toISOString(),
    userId: req.user.sub,
    userLogin: req.user.login,
    action,
    resource,
    ipAddress: req.headers['x-forwarded-for'] || req.socket.remoteAddress,
    userAgent: req.headers['user-agent'],
    ...metadata
  };
  
  // Append to audit log in Azure Blob
  const logLine = JSON.stringify(log) + '\n';
  const date = new Date().toISOString().split('T')[0];
  
  await appendToBlob(
    'audit-logs',
    `${date}.jsonl`,
    logLine
  );
}

// Usage in API route
export default requirePermission('canReadFlights')(async (req, res) => {
  try {
    const result = await queryFlights(req.user, req.permissions, req.query);
    
    await logAccess(req, 'read', 'flights', {
      query: req.query,
      rowCount: result.length,
      success: true
    });
    
    res.json(result);
  } catch (error) {
    await logAccess(req, 'read', 'flights', {
      query: req.query,
      success: false,
      error: error.message
    });
    
    throw error;
  }
});
```

## Performance Characteristics

### Query Performance

**Small dataset (< 10k flights):**
- Query time: 100-500ms
- DuckDB reads and parses JSONL directly from Azure

**Medium dataset (10k-100k flights):**
- Query time: 500ms-2s
- Partition by date helps (read only relevant files)

**Large dataset (> 100k flights):**
- Consider converting JSONL → Parquet (10x faster)
- DuckDB can write Parquet back to Azure

### Cost Analysis

**30k flights @ 5KB each = 150MB**

- Storage: 150MB × $0.018/GB = **$0.0027/month**
- Reads: 10k queries/day × 30 days = 300k reads = **$0.12/month**
- Egress: First 100GB free
- **Total: ~$0.12/month**

**Compare to:**
- PostgreSQL on Azure: ~$15/month minimum
- MongoDB Atlas: ~$25/month minimum
- Synapse Serverless: ~$5/TB queried

## Summary

### ✅ Query Requirements Met

| Requirement | Solution |
|-------------|----------|
| Filter by status | WHERE status = 'successful' |
| Count by destination | GROUP BY with JSON extraction |
| Time-series analysis | DATE_TRUNC with aggregates |
| Failure Pareto | GROUP BY with window functions |
| International tracking | Filter on isInternational flag |
| Multi-user isolation | Row-Level Security filters |

### ✅ Security Requirements Met

| Requirement | Solution |
|-------------|----------|
| Authentication | GitHub OAuth + JWT |
| Authorization | RBAC (viewer/contributor/admin) |
| Encryption at rest | Azure Blob AES-256 |
| Encryption in transit | HTTPS/TLS 1.2+ |
| Access control | Time-limited SAS tokens |
| Row-level security | DuckDB WHERE filters |
| Audit logging | JSONL append logs |
| No credential storage | OAuth + managed tokens |

### 🚀 Key Benefits

1. **No database server** - Serverless, zero ops
2. **Direct cloud queries** - No ETL, no staging
3. **Cost effective** - Pay only for storage + reads
4. **Secure by design** - Multiple layers of security
5. **Scalable** - Handles 100k+ flights easily
6. **Fast analytics** - Columnar execution
7. **GitHub integration** - Native auth/authz

## Next Steps

1. [ ] Setup Azure Blob Storage
2. [ ] Configure GitHub OAuth app
3. [ ] Implement JWT middleware
4. [ ] Build DuckDB query service
5. [ ] Create dashboard API routes
6. [ ] Test with sample flight data
