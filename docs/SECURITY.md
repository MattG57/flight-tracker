# Security Architecture

## Overview

Flight Tracker implements defense-in-depth security with multiple layers:

1. **Authentication** - GitHub OAuth (who are you?)
2. **Authorization** - JWT + RBAC (what can you do?)
3. **Data Encryption** - At rest and in transit
4. **Access Control** - Time-limited SAS tokens
5. **Row-Level Security** - DuckDB filtering
6. **Audit Logging** - Track all data access

## Authentication Flow

### GitHub OAuth

```
┌──────┐                 ┌─────────┐                ┌────────┐
│ User │                 │Dashboard│                │ GitHub │
└──┬───┘                 └────┬────┘                └───┬────┘
   │                          │                         │
   │ 1. Click "Login"         │                         │
   │─────────────────────────>│                         │
   │                          │                         │
   │                          │ 2. Redirect to OAuth    │
   │                          │────────────────────────>│
   │                          │                         │
   │ 3. Authorize app         │                         │
   │<─────────────────────────┼─────────────────────────│
   │                          │                         │
   │ 4. Callback with code    │                         │
   │─────────────────────────>│                         │
   │                          │                         │
   │                          │ 5. Exchange code        │
   │                          │────────────────────────>│
   │                          │                         │
   │                          │ 6. Return access token  │
   │                          │<────────────────────────│
   │                          │                         │
   │                          │ 7. Get user info        │
   │                          │────────────────────────>│
   │                          │                         │
   │                          │ 8. Return profile + orgs│
   │                          │<────────────────────────│
   │                          │                         │
   │ 9. Issue JWT             │                         │
   │<─────────────────────────│                         │
   │                          │                         │
```

### Implementation

```typescript
// pages/api/auth/github.ts
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const { code } = req.query;
  
  // Exchange code for access token
  const tokenResponse = await fetch('https://github.com/login/oauth/access_token', {
    method: 'POST',
    headers: { 'Accept': 'application/json' },
    body: JSON.stringify({
      client_id: process.env.GITHUB_CLIENT_ID,
      client_secret: process.env.GITHUB_CLIENT_SECRET,
      code
    })
  });
  
  const { access_token } = await tokenResponse.json();
  
  // Get user info
  const userResponse = await fetch('https://api.github.com/user', {
    headers: { 'Authorization': `Bearer ${access_token}` }
  });
  const user = await userResponse.json();
  
  // Get org memberships
  const orgsResponse = await fetch('https://api.github.com/user/orgs', {
    headers: { 'Authorization': `Bearer ${access_token}` }
  });
  const orgs = await orgsResponse.json();
  
  // Check authorization
  const isAuthorized = orgs.some(org => org.login === process.env.AUTHORIZED_ORG);
  if (!isAuthorized) {
    return res.status(403).json({ error: 'Not authorized' });
  }
  
  // Issue JWT
  const jwt = sign({
    sub: user.id,
    login: user.login,
    name: user.name,
    orgs: orgs.map(o => o.login),
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours
  }, process.env.JWT_SECRET);
  
  // Set secure cookie
  res.setHeader('Set-Cookie', `token=${jwt}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=86400`);
  res.redirect('/dashboard');
}
```

## Authorization Model

### Role-Based Access Control (RBAC)

```typescript
enum Role {
  VIEWER = 'viewer',      // Read flights
  CONTRIBUTOR = 'contributor', // Read + write flights
  ADMIN = 'admin'         // Full access
}

enum Scope {
  OWN = 'own',           // Only own flights
  TEAM = 'team',         // Team flights
  ORG = 'org',           // Organization flights
  ALL = 'all'            // All flights (admin)
}

interface Permissions {
  role: Role;
  scope: Scope;
  canReadFlights: boolean;
  canWriteFlights: boolean;
  canDeleteFlights: boolean;
  canManageUsers: boolean;
}

// Derive permissions from GitHub org/team membership
async function getPermissions(user: JWTPayload): Promise<Permissions> {
  // Check team membership via GitHub API
  const teams = await getTeamMemberships(user.login);
  
  const isAdmin = teams.includes('flight-tracker-admins');
  const isContributor = teams.includes('flight-tracker-contributors');
  
  if (isAdmin) {
    return {
      role: Role.ADMIN,
      scope: Scope.ALL,
      canReadFlights: true,
      canWriteFlights: true,
      canDeleteFlights: true,
      canManageUsers: true
    };
  }
  
  if (isContributor) {
    return {
      role: Role.CONTRIBUTOR,
      scope: Scope.TEAM,
      canReadFlights: true,
      canWriteFlights: true,
      canDeleteFlights: false,
      canManageUsers: false
    };
  }
  
  // Default: viewer with own scope
  return {
    role: Role.VIEWER,
    scope: Scope.OWN,
    canReadFlights: true,
    canWriteFlights: false,
    canDeleteFlights: false,
    canManageUsers: false
  };
}
```

### JWT Middleware

```typescript
// middleware/auth.ts
import { verify } from 'jsonwebtoken';

export function requireAuth(handler: NextApiHandler): NextApiHandler {
  return async (req, res) => {
    const token = req.cookies.token || req.headers.authorization?.replace('Bearer ', '');
    
    if (!token) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    
    try {
      const payload = verify(token, process.env.JWT_SECRET);
      req.user = payload;
      return handler(req, res);
    } catch (err) {
      return res.status(401).json({ error: 'Invalid token' });
    }
  };
}

export function requirePermission(permission: keyof Permissions) {
  return (handler: NextApiHandler): NextApiHandler => {
    return requireAuth(async (req, res) => {
      const permissions = await getPermissions(req.user);
      
      if (!permissions[permission]) {
        return res.status(403).json({ error: 'Forbidden' });
      }
      
      req.permissions = permissions;
      return handler(req, res);
    });
  };
}

// Usage:
export default requirePermission('canReadFlights')(async (req, res) => {
  // Handler code
});
```

## Data Encryption

### At Rest (Azure Blob Storage)

Azure automatically encrypts all data at rest using AES-256 encryption.

**Option 1: Microsoft-Managed Keys (Default)**
```typescript
// Automatic - no configuration needed
// Azure manages encryption keys
```

**Option 2: Customer-Managed Keys (Advanced)**
```typescript
// Store keys in Azure Key Vault
const storageAccount = {
  encryption: {
    services: { blob: { enabled: true } },
    keySource: 'Microsoft.Keyvault',
    keyVaultProperties: {
      keyName: 'flight-tracker-key',
      keyVaultUri: 'https://your-keyvault.vault.azure.net'
    }
  }
};
```

### In Transit

**All connections use HTTPS/TLS 1.2+**

```typescript
// Enforce HTTPS in Next.js
// next.config.js
module.exports = {
  async headers() {
    return [{
      source: '/:path*',
      headers: [
        {
          key: 'Strict-Transport-Security',
          value: 'max-age=63072000; includeSubDomains; preload'
        }
      ]
    }];
  }
};

// Azure Blob: HTTPS-only
az storage account update \
  --name flighttracker \
  --https-only true
```

## Access Control

### Shared Access Signatures (SAS)

Time-limited, permission-scoped tokens for Azure Blob access:

```typescript
import { generateBlobSASQueryParameters, BlobSASPermissions, StorageSharedKeyCredential } from '@azure/storage-blob';

function generateSASToken(
  user: JWTPayload,
  permissions: Permissions,
  durationMinutes: number = 60
): string {
  const sasPermissions = new BlobSASPermissions();
  sasPermissions.read = permissions.canReadFlights;
  sasPermissions.write = permissions.canWriteFlights;
  sasPermissions.delete = permissions.canDeleteFlights;
  
  const startsOn = new Date();
  const expiresOn = new Date(Date.now() + durationMinutes * 60 * 1000);
  
  const credential = new StorageSharedKeyCredential(
    process.env.AZURE_STORAGE_ACCOUNT,
    process.env.AZURE_STORAGE_KEY
  );
  
  return generateBlobSASQueryParameters({
    containerName: 'flight-tracker-data',
    permissions: sasPermissions,
    startsOn,
    expiresOn,
    protocol: 'https',
    // Optional: Restrict to IP range
    ipRange: { start: '0.0.0.0', end: '255.255.255.255' }
  }, credential).toString();
}

// Usage in API route:
export default requirePermission('canReadFlights')(async (req, res) => {
  const sasToken = generateSASToken(req.user, req.permissions, 60); // 1 hour
  
  // Return SAS token to client for direct Azure access
  res.json({ sasToken });
});
```

### Row-Level Security (RLS)

Filter data in DuckDB queries based on user permissions:

```typescript
async function queryFlights(
  user: JWTPayload,
  permissions: Permissions,
  filters: QueryFilters
) {
  let whereClause = 'WHERE 1=1';
  
  // Apply RLS based on scope
  switch (permissions.scope) {
    case Scope.OWN:
      whereClause += ` AND created_by = '${user.login}'`;
      break;
    case Scope.TEAM:
      const teamMembers = await getTeamMembers(user.teams);
      whereClause += ` AND created_by IN (${teamMembers.map(m => `'${m}'`).join(',')})`;
      break;
    case Scope.ORG:
      whereClause += ` AND org_id = '${user.orgs[0]}'`;
      break;
    case Scope.ALL:
      // No filter - admin sees all
      break;
  }
  
  // Apply user filters
  if (filters.status) {
    whereClause += ` AND status = '${filters.status}'`;
  }
  if (filters.startDate) {
    whereClause += ` AND timestamp >= '${filters.startDate}'`;
  }
  
  const sasToken = generateSASToken(user, permissions);
  
  return db.query(`
    SELECT 
      flight_id,
      timestamp,
      created_by,
      status,
      cost,
      duration
    FROM read_json('azure://flight-tracker-data/flights/**/*.jsonl?${sasToken}')
    ${whereClause}
    ORDER BY timestamp DESC
    LIMIT 1000
  `);
}
```

## Audit Logging

Track all data access for security and compliance:

```typescript
interface AuditLog {
  timestamp: string;
  user_id: string;
  user_login: string;
  action: 'read' | 'write' | 'delete';
  resource: string;
  ip_address: string;
  user_agent: string;
  query: string;
  row_count: number;
  success: boolean;
  error?: string;
}

async function logAccess(req: NextApiRequest, action: string, resource: string, metadata: any) {
  const log: AuditLog = {
    timestamp: new Date().toISOString(),
    user_id: req.user.sub,
    user_login: req.user.login,
    action,
    resource,
    ip_address: req.headers['x-forwarded-for'] || req.socket.remoteAddress,
    user_agent: req.headers['user-agent'],
    ...metadata
  };
  
  // Append to audit log in Azure Blob
  await appendToBlob('audit-logs', `${new Date().toISOString().split('T')[0]}.jsonl`, 
    JSON.stringify(log) + '\n'
  );
}

// Wrap queries with audit logging
export default requirePermission('canReadFlights')(async (req, res) => {
  try {
    const result = await queryFlights(req.user, req.permissions, req.query);
    
    await logAccess(req, 'read', 'flights', {
      query: req.query,
      row_count: result.length,
      success: true
    });
    
    res.json(result);
  } catch (error) {
    await logAccess(req, 'read', 'flights', {
      query: req.query,
      success: false,
      error: error.message
    });
    
    res.status(500).json({ error: 'Query failed' });
  }
});
```

## Security Checklist

- [ ] GitHub OAuth configured with authorized org
- [ ] JWT secret generated and stored securely
- [ ] Azure Blob Storage encryption enabled
- [ ] HTTPS enforced (Next.js + Azure)
- [ ] SAS tokens time-limited (max 1 hour)
- [ ] Row-level security implemented
- [ ] Audit logging enabled
- [ ] Rate limiting on API routes
- [ ] CORS configured (restrict origins)
- [ ] CSP headers configured
- [ ] Dependency scanning (Dependabot)
- [ ] Secret scanning enabled (GitHub)

## Threat Model

### Threats & Mitigations

| Threat | Mitigation |
|--------|-----------|
| Unauthorized access | GitHub OAuth + JWT + org membership check |
| Token theft | Short-lived tokens (24h JWT, 1h SAS), HttpOnly cookies, HTTPS only |
| Data exfiltration | RLS filters, audit logging, rate limiting |
| MITM attacks | HTTPS/TLS 1.2+, HSTS headers |
| XSS attacks | CSP headers, sanitize user input |
| SQL injection | Parameterized queries in DuckDB |
| Brute force | Rate limiting (429 responses) |
| Data tampering | Append-only storage, audit logs |

## Incident Response

### If Token Compromised:

1. Rotate JWT secret immediately
2. Invalidate all active sessions
3. Review audit logs for suspicious activity
4. Notify affected users
5. Force re-authentication

### If Data Breach:

1. Revoke all SAS tokens
2. Rotate Azure Storage keys
3. Review audit logs
4. Investigate scope of breach
5. Notify users if PII exposed
6. Document and remediate root cause

## Compliance Considerations

- **GDPR**: Right to erasure (delete user data), data portability (export JSON)
- **SOC 2**: Audit logging, access controls, encryption at rest/transit
- **HIPAA**: Customer-managed keys, audit trails (if handling health data)

For production deployments, consult with security team and conduct penetration testing.
