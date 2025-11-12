# Data Storage Strategy

## DuckDB + Cloud Storage Architecture

Flight Tracker uses **DuckDB** as the query engine with cloud storage (Azure Blob or S3) for data persistence.

### Why DuckDB?

- **Embedded analytics engine** - No database server to manage
- **Query cloud storage directly** - Read JSON/Parquet from Azure/S3 without loading into DB
- **Fast analytics** - Columnar storage, vectorized execution, parallel processing
- **Cost effective** - Only pay for storage + minimal compute
- **Flexible** - Runs in browser, Node.js, Python, CLI

## Storage Layout

```
azure://flight-tracker-data/
├── flights/
│   ├── 2024/
│   │   ├── 11/
│   │   │   ├── 12/
│   │   │   │   └── flights.jsonl    # Newline-delimited JSON
│   │   │   └── 13/
│   │   └── 12/
│   └── metadata.json
└── users/
    └── access-log.jsonl
```

### Data Format: JSONL (JSON Lines)

Each line is a complete JSON object for a single flight:

```jsonl
{"flightId":"f-001","timestamp":"2024-11-12T10:00:00Z","status":"success","cost":0.45}
{"flightId":"f-002","timestamp":"2024-11-12T10:15:00Z","status":"failure","cost":0.12}
```

**Benefits:**
- Append-only (no file rewrites)
- Streamable (process line by line)
- DuckDB native support
- Easy to partition by date

## Authentication & Authorization

### GitHub OAuth Integration

```
User → Dashboard → GitHub OAuth → JWT Token → API Gateway → Azure Blob (SAS Token)
```

#### Flow:

1. **User Login**
   ```typescript
   // User clicks "Login with GitHub"
   redirectTo('https://github.com/login/oauth/authorize?client_id=...')
   ```

2. **OAuth Callback**
   ```typescript
   // Exchange code for GitHub user info
   const user = await getGitHubUser(code);
   // Check authorization (org membership, team, etc.)
   const isAuthorized = await checkAccess(user);
   ```

3. **Issue JWT**
   ```typescript
   // Sign JWT with user claims
   const token = jwt.sign({
     sub: user.id,
     login: user.login,
     orgs: user.organizations,
     scope: ['read:flights', 'write:flights']
   }, SECRET, { expiresIn: '24h' });
   ```

4. **Access Data**
   ```typescript
   // API validates JWT and generates time-limited SAS token
   const sasToken = generateAzureSAS({
     permissions: 'r', // read-only
     expiresIn: '1h',
     userContext: jwt.sub
   });
   
   // Dashboard queries with DuckDB
   const result = await db.query(`
     SELECT * FROM read_json('azure://flight-tracker-data/flights/**/*.jsonl?${sasToken}')
     WHERE timestamp > '2024-11-01'
   `);
   ```

### Authorization Levels

```typescript
interface UserPermissions {
  canReadFlights: boolean;      // View dashboard
  canWriteFlights: boolean;     // Create flight plans
  canDeleteFlights: boolean;    // Admin only
  canViewAllUsers: boolean;     // Admin only
  scope: 'own' | 'team' | 'org' | 'all'; // Data visibility
}

// Example: Check GitHub org membership
async function checkAccess(githubUser: GitHubUser): Promise<UserPermissions> {
  const isMember = await isOrgMember(githubUser, 'your-github-org');
  const isTeamMember = await isTeamMember(githubUser, 'flight-tracker-users');
  const isAdmin = await isTeamMember(githubUser, 'flight-tracker-admins');
  
  return {
    canReadFlights: isMember || isTeamMember,
    canWriteFlights: isTeamMember,
    canDeleteFlights: isAdmin,
    canViewAllUsers: isAdmin,
    scope: isAdmin ? 'all' : 'team'
  };
}
```

## Security Architecture

### 1. Data Encryption

**At Rest:**
```typescript
// Azure Blob Storage - encryption enabled by default (AES-256)
// Or use Customer-Managed Keys (CMK) via Azure Key Vault
const storageAccount = {
  encryption: {
    services: { blob: { enabled: true } },
    keySource: 'Microsoft.Storage', // or 'Microsoft.Keyvault'
  }
};
```

**In Transit:**
- HTTPS only (TLS 1.2+)
- Azure enforces encryption in transit by default

### 2. Azure Blob Access Control

**Shared Access Signatures (SAS) - Time-limited tokens:**

```typescript
import { generateBlobSASQueryParameters, BlobSASPermissions } from '@azure/storage-blob';

function generateSASToken(userPermissions: UserPermissions) {
  const permissions = new BlobSASPermissions();
  permissions.read = userPermissions.canReadFlights;
  permissions.write = userPermissions.canWriteFlights;
  permissions.delete = userPermissions.canDeleteFlights;
  
  return generateBlobSASQueryParameters({
    containerName: 'flight-tracker-data',
    permissions,
    startsOn: new Date(),
    expiresOn: new Date(Date.now() + 60 * 60 * 1000), // 1 hour
    protocol: 'https'
  }, credential).toString();
}
```

**Row-Level Security (RLS) via DuckDB:**

```sql
-- Filter data based on user scope
SELECT * FROM read_json('azure://flight-tracker-data/flights/**/*.jsonl')
WHERE 
  CASE 
    WHEN :userScope = 'all' THEN true
    WHEN :userScope = 'team' THEN team_id = :userTeamId
    WHEN :userScope = 'own' THEN created_by = :userId
    ELSE false
  END
```

### 3. API Gateway Architecture

```typescript
// Next.js API route example
// /api/flights/query

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  // 1. Validate JWT
  const token = req.headers.authorization?.replace('Bearer ', '');
  const user = jwt.verify(token, SECRET);
  
  // 2. Check permissions
  const permissions = await getPermissions(user);
  if (!permissions.canReadFlights) {
    return res.status(403).json({ error: 'Forbidden' });
  }
  
  // 3. Generate SAS token
  const sasToken = generateSASToken(permissions);
  
  // 4. Query with DuckDB (server-side)
  const db = await DuckDB.create();
  const result = await db.query(`
    SELECT * FROM read_json('azure://flight-tracker-data/flights/**/*.jsonl?${sasToken}')
    WHERE created_by = $1 OR $2 = 'all'
    LIMIT 1000
  `, [user.id, permissions.scope]);
  
  // 5. Return filtered data
  res.json(result);
}
```

## Multi-User Isolation

### Option A: Path-based Isolation

```
azure://flight-tracker-data/
├── users/
│   ├── user-123/
│   │   └── flights/*.jsonl
│   └── user-456/
│       └── flights/*.jsonl
└── shared/
    └── flights/*.jsonl
```

**Query with user context:**
```sql
SELECT * FROM read_json('azure://flight-tracker-data/users/:userId/flights/**/*.jsonl')
UNION ALL
SELECT * FROM read_json('azure://flight-tracker-data/shared/flights/**/*.jsonl')
```

### Option B: Attribute-based (Preferred)

Store all flights together, filter by attributes:

```jsonl
{"flightId":"f-001","userId":"user-123","teamId":"team-a","visibility":"private"}
{"flightId":"f-002","userId":"user-456","teamId":"team-a","visibility":"team"}
{"flightId":"f-003","userId":"user-123","teamId":"team-b","visibility":"public"}
```

**DuckDB query with RLS:**
```typescript
async function queryFlights(user: User, permissions: Permissions) {
  let whereClause = 'WHERE 1=1';
  
  if (permissions.scope === 'own') {
    whereClause += ` AND userId = '${user.id}'`;
  } else if (permissions.scope === 'team') {
    whereClause += ` AND (userId = '${user.id}' OR teamId IN (${user.teams.join(',')}))`;
  } else if (permissions.scope === 'org') {
    whereClause += ` AND orgId = '${user.orgId}'`;
  }
  // 'all' scope: no additional filter
  
  return db.query(`
    SELECT * FROM read_json('azure://flight-tracker-data/flights/**/*.jsonl')
    ${whereClause}
  `);
}
```

## Deployment Architecture

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │ HTTPS
       ▼
┌─────────────────────┐
│  Next.js Dashboard  │
│  (Vercel/Azure)     │
└──────┬──────────────┘
       │
       ├─► GitHub OAuth API
       │   (Authentication)
       │
       ├─► DuckDB WASM (Client-side)
       │   └─► Azure Blob (via SAS)
       │
       └─► API Routes (Server-side)
           ├─► JWT validation
           ├─► Authorization check
           ├─► SAS token generation
           └─► DuckDB queries
               └─► Azure Blob Storage
                   (Encrypted at rest)
```

## Cost Estimation

### Azure Blob Storage:
- **Storage**: $0.018/GB/month (Hot tier)
- **Transactions**: $0.004 per 10k reads
- **Egress**: First 100GB free/month

### Example (1000 flights/day, 5KB each):
- **Storage**: 5MB/day × 30 days = 150MB = **$0.0027/month**
- **Reads**: 10k queries/day = **$0.012/month**
- **Total**: **~$0.10/month** for 30k flights

### DuckDB:
- **Free** (runs in dashboard)

### Next.js on Vercel:
- **Free tier**: 100GB bandwidth, sufficient for pilot

## Getting Started

### 1. Setup Azure Blob Storage

```bash
# Create storage account
az storage account create \
  --name flighttracker \
  --resource-group flight-tracker-rg \
  --location eastus \
  --sku Standard_LRS \
  --encryption-services blob \
  --https-only true

# Create container
az storage container create \
  --account-name flighttracker \
  --name flight-tracker-data \
  --public-access off
```

### 2. Configure GitHub OAuth App

1. Go to GitHub Settings → Developer settings → OAuth Apps
2. Create new OAuth App:
   - **Application name**: Flight Tracker
   - **Homepage URL**: https://your-dashboard.vercel.app
   - **Authorization callback URL**: https://your-dashboard.vercel.app/api/auth/callback
3. Save `CLIENT_ID` and `CLIENT_SECRET`

### 3. Environment Variables

```env
# .env.local
AZURE_STORAGE_ACCOUNT=flighttracker
AZURE_STORAGE_KEY=...
AZURE_STORAGE_CONTAINER=flight-tracker-data

GITHUB_CLIENT_ID=...
GITHUB_CLIENT_SECRET=...
JWT_SECRET=... # Generate: openssl rand -base64 32

AUTHORIZED_ORG=your-github-org
ADMIN_TEAM=flight-tracker-admins
```

## Next Steps

- [ ] Implement GitHub OAuth flow
- [ ] Setup Azure Blob Storage
- [ ] Create JWT middleware
- [ ] Build DuckDB query layer with RLS
- [ ] Add audit logging
- [ ] Setup monitoring (Azure Monitor)
