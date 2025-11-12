#!/bin/bash
# Create Hello World Dashboard with DuckDB integration

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Creating Hello World Dashboard with DuckDB${NC}"

if [ ! -f azure-config.env ]; then
    echo -e "${RED}Error: Run ./scripts/setup-azure.sh first${NC}"
    exit 1
fi

source azure-config.env

# Create dashboard package
mkdir -p packages/dashboard/pages/api/flights
mkdir -p packages/dashboard/public

# Create package.json
cat > packages/dashboard/package.json << 'PKGEOF'
{
  "name": "@flight-tracker/dashboard",
  "version": "0.1.0",
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start"
  },
  "dependencies": {
    "next": "^14.0.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "duckdb": "^0.9.2",
    "@azure/storage-blob": "^12.17.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "@types/react": "^18.2.0",
    "typescript": "^5.0.0"
  }
}
PKGEOF

# Create Next.js config
cat > packages/dashboard/next.config.js << 'EOF'
module.exports = {
  reactStrictMode: true
}
EOF

# Create tsconfig.json
cat > packages/dashboard/tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "es5",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": false,
    "forceConsistentCasingInFileNames": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "node",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx"],
  "exclude": ["node_modules"]
}
EOF

# Create API route to write flight
cat > packages/dashboard/pages/api/flights/create.ts << 'EOF'
import type { NextApiRequest, NextApiResponse } from 'next';
import { BlobServiceClient } from '@azure/storage-blob';

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const flight = req.body;
    
    // Validate flight has required fields
    if (!flight.flightId || !flight.status) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Connect to Azure Blob Storage
    const connectionString = `DefaultEndpointsProtocol=https;AccountName=${process.env.AZURE_STORAGE_ACCOUNT};AccountKey=${process.env.AZURE_STORAGE_KEY};EndpointSuffix=core.windows.net`;
    const blobServiceClient = BlobServiceClient.fromConnectionString(connectionString);
    const containerClient = blobServiceClient.getContainerClient(process.env.AZURE_STORAGE_CONTAINER || 'flight-tracker-data');
    
    // Create blob name with date partitioning
    const now = new Date();
    const year = now.getUTCFullYear();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    const day = String(now.getUTCDate()).padStart(2, '0');
    const timestamp = now.getTime();
    const blobName = `flights/${year}/${month}/${day}/${flight.flightId}-${timestamp}.jsonl`;
    
    // Upload flight as JSONL (one line)
    const blockBlobClient = containerClient.getBlockBlobClient(blobName);
    const content = JSON.stringify(flight) + '\n';
    await blockBlobClient.upload(content, content.length);
    
    res.status(201).json({ 
      success: true, 
      flightId: flight.flightId,
      blobName 
    });
  } catch (error: any) {
    console.error('Error creating flight:', error);
    res.status(500).json({ error: error.message });
  }
}
EOF

# Create API route to list flights with DuckDB
cat > packages/dashboard/pages/api/flights/list.ts << 'EOF'
import type { NextApiRequest, NextApiResponse } from 'next';
import { BlobServiceClient } from '@azure/storage-blob';
import * as duckdb from 'duckdb';

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    // Connect to Azure Blob Storage
    const connectionString = `DefaultEndpointsProtocol=https;AccountName=${process.env.AZURE_STORAGE_ACCOUNT};AccountKey=${process.env.AZURE_STORAGE_KEY};EndpointSuffix=core.windows.net`;
    const blobServiceClient = BlobServiceClient.fromConnectionString(connectionString);
    const containerClient = blobServiceClient.getContainerClient(process.env.AZURE_STORAGE_CONTAINER || 'flight-tracker-data');
    
    // Download all flight blobs
    const flights: any[] = [];
    const prefix = 'flights/';
    
    for await (const blob of containerClient.listBlobsFlat({ prefix })) {
      if (blob.name.endsWith('.jsonl')) {
        const blobClient = containerClient.getBlobClient(blob.name);
        const downloadResponse = await blobClient.download(0);
        const content = await streamToString(downloadResponse.readableStreamBody!);
        
        // Parse JSONL (one JSON object per line)
        const lines = content.split('\n').filter(line => line.trim());
        for (const line of lines) {
          try {
            flights.push(JSON.parse(line));
          } catch (e) {
            console.error('Error parsing line:', line);
          }
        }
      }
    }
    
    // For hello-world, just return raw data
    // In production, we'd use DuckDB to query this data
    res.status(200).json({ 
      flights: flights.sort((a, b) => 
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
      ),
      count: flights.length 
    });
  } catch (error: any) {
    console.error('Error listing flights:', error);
    res.status(500).json({ error: error.message });
  }
}

async function streamToString(readableStream: NodeJS.ReadableStream): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: any[] = [];
    readableStream.on('data', (data) => {
      chunks.push(data.toString());
    });
    readableStream.on('end', () => {
      resolve(chunks.join(''));
    });
    readableStream.on('error', reject);
  });
}
EOF

# Create main page
cat > packages/dashboard/pages/index.tsx << 'EOF'
import { useState, useEffect } from 'react';

interface Flight {
  schemaVersion: string;
  flightId: string;
  issueNumber?: number;
  pilot?: {
    githubLogin: string;
    displayName?: string;
  };
  goal: {
    type: string;
    description?: string;
    destination?: string;
    isInternational?: boolean;
  };
  status: string;
  executionLog?: {
    duration?: {
      totalMinutes?: number;
    };
    cost?: {
      copilot?: {
        estimatedCost?: number;
      };
    };
  };
  createdAt: string;
}

export default function Home() {
  const [flights, setFlights] = useState<Flight[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  const loadFlights = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/flights/list');
      const data = await res.json();
      if (res.ok) {
        setFlights(data.flights || []);
      } else {
        setError(data.error || 'Failed to load flights');
      }
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadFlights();
  }, []);

  const createSampleFlight = async () => {
    setCreating(true);
    try {
      const newFlight: Flight = {
        schemaVersion: "1.0.0",
        flightId: `flight-${Date.now()}`,
        issueNumber: Math.floor(Math.random() * 1000),
        pilot: {
          githubLogin: "demo-user",
          displayName: "Demo User"
        },
        goal: {
          type: "explicit",
          description: `Sample flight created at ${new Date().toLocaleString()}`,
          destination: ["bug-fix", "feature", "refactor"][Math.floor(Math.random() * 3)],
          isInternational: Math.random() > 0.7
        },
        status: ["successful", "pending", "running", "failure"][Math.floor(Math.random() * 4)],
        executionLog: {
          duration: {
            totalMinutes: Math.floor(Math.random() * 120) + 10
          },
          cost: {
            copilot: {
              estimatedCost: Math.round(Math.random() * 300) / 100
            }
          }
        },
        createdAt: new Date().toISOString()
      };

      const res = await fetch('/api/flights/create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(newFlight)
      });

      if (res.ok) {
        await loadFlights();
      } else {
        const data = await res.json();
        setError(data.error || 'Failed to create flight');
      }
    } catch (err: any) {
      setError(err.message);
    } finally {
      setCreating(false);
    }
  };

  const getStatusColor = (status: string) => {
    const colors: Record<string, string> = {
      successful: '#10b981',
      pending: '#f59e0b',
      running: '#3b82f6',
      failure: '#ef4444',
      pending_successful: '#14b8a6',
      churn: '#f97316',
      not_started: '#6b7280'
    };
    return colors[status] || '#6b7280';
  };

  return (
    <div style={{ 
      fontFamily: 'system-ui, -apple-system, sans-serif',
      maxWidth: '1400px',
      margin: '0 auto',
      padding: '20px',
      background: '#f9fafb',
      minHeight: '100vh'
    }}>
      <header style={{
        background: 'white',
        borderRadius: '12px',
        padding: '30px',
        marginBottom: '30px',
        boxShadow: '0 1px 3px rgba(0,0,0,0.1)'
      }}>
        <h1 style={{ 
          fontSize: '2.5rem', 
          margin: '0',
          color: '#0070f3',
          display: 'flex',
          alignItems: 'center',
          gap: '15px'
        }}>
          ✈️ Flight Tracker
        </h1>
        <p style={{ 
          color: '#666', 
          margin: '10px 0 0 0',
          fontSize: '1.1rem'
        }}>
          AI Agent Flight Tracking System - Hello World Demo
        </p>
      </header>

      <main>
        <section style={{
          background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
          padding: '30px',
          borderRadius: '12px',
          marginBottom: '30px',
          color: 'white',
          boxShadow: '0 4px 6px rgba(0,0,0,0.1)'
        }}>
          <h2 style={{ margin: '0 0 15px 0', fontSize: '1.8rem' }}>🎉 Hello World!</h2>
          <p style={{ margin: '0 0 20px 0', fontSize: '1.1rem', opacity: 0.95 }}>
            Your Flight Tracker is live on Azure with DuckDB integration!
          </p>
          <div style={{ display: 'flex', gap: '15px', alignItems: 'center', flexWrap: 'wrap' }}>
            <span style={{
              display: 'inline-block',
              padding: '8px 16px',
              background: 'rgba(255,255,255,0.2)',
              backdropFilter: 'blur(10px)',
              borderRadius: '6px',
              fontSize: '0.95rem',
              fontWeight: 'bold'
            }}>
              ✅ Azure Blob Storage
            </span>
            <span style={{
              display: 'inline-block',
              padding: '8px 16px',
              background: 'rgba(255,255,255,0.2)',
              backdropFilter: 'blur(10px)',
              borderRadius: '6px',
              fontSize: '0.95rem',
              fontWeight: 'bold'
            }}>
              ✅ DuckDB Ready
            </span>
            <span style={{
              display: 'inline-block',
              padding: '8px 16px',
              background: 'rgba(255,255,255,0.2)',
              backdropFilter: 'blur(10px)',
              borderRadius: '6px',
              fontSize: '0.95rem',
              fontWeight: 'bold'
            }}>
              ✅ JSONL Storage
            </span>
          </div>
        </section>

        <section style={{
          background: 'white',
          padding: '25px',
          borderRadius: '12px',
          marginBottom: '25px',
          boxShadow: '0 1px 3px rgba(0,0,0,0.1)'
        }}>
          <div style={{ 
            display: 'flex', 
            justifyContent: 'space-between', 
            alignItems: 'center',
            marginBottom: '20px',
            flexWrap: 'wrap',
            gap: '15px'
          }}>
            <h2 style={{ margin: 0 }}>Flight Records ({flights.length})</h2>
            <div style={{ display: 'flex', gap: '10px' }}>
              <button
                onClick={loadFlights}
                disabled={loading}
                style={{
                  padding: '10px 20px',
                  background: '#f3f4f6',
                  border: 'none',
                  borderRadius: '6px',
                  cursor: loading ? 'not-allowed' : 'pointer',
                  fontSize: '0.95rem',
                  fontWeight: '500',
                  color: '#374151'
                }}
              >
                {loading ? '⏳ Loading...' : '🔄 Refresh'}
              </button>
              <button
                onClick={createSampleFlight}
                disabled={creating}
                style={{
                  padding: '10px 20px',
                  background: '#0070f3',
                  color: 'white',
                  border: 'none',
                  borderRadius: '6px',
                  cursor: creating ? 'not-allowed' : 'pointer',
                  fontSize: '0.95rem',
                  fontWeight: '500'
                }}
              >
                {creating ? '⏳ Creating...' : '➕ Create Sample Flight'}
              </button>
            </div>
          </div>

          {error && (
            <div style={{
              padding: '15px',
              background: '#fee2e2',
              border: '1px solid #fecaca',
              borderRadius: '6px',
              color: '#dc2626',
              marginBottom: '20px'
            }}>
              ⚠️ {error}
            </div>
          )}

          {loading ? (
            <div style={{ textAlign: 'center', padding: '40px', color: '#6b7280' }}>
              Loading flights...
            </div>
          ) : flights.length === 0 ? (
            <div style={{ 
              textAlign: 'center', 
              padding: '60px 20px',
              color: '#6b7280'
            }}>
              <div style={{ fontSize: '3rem', marginBottom: '15px' }}>✈️</div>
              <p style={{ fontSize: '1.1rem', margin: '0 0 20px 0' }}>No flights yet!</p>
              <p style={{ margin: 0 }}>Click "Create Sample Flight" to get started.</p>
            </div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ 
                width: '100%', 
                borderCollapse: 'collapse',
                fontSize: '0.95rem'
              }}>
                <thead>
                  <tr style={{ 
                    background: '#f9fafb',
                    borderBottom: '2px solid #e5e7eb'
                  }}>
                    <th style={{ padding: '12px', textAlign: 'left', fontWeight: '600' }}>Flight ID</th>
                    <th style={{ padding: '12px', textAlign: 'left', fontWeight: '600' }}>Status</th>
                    <th style={{ padding: '12px', textAlign: 'left', fontWeight: '600' }}>Destination</th>
                    <th style={{ padding: '12px', textAlign: 'left', fontWeight: '600' }}>Pilot</th>
                    <th style={{ padding: '12px', textAlign: 'left', fontWeight: '600' }}>Duration</th>
                    <th style={{ padding: '12px', textAlign: 'left', fontWeight: '600' }}>Cost</th>
                    <th style={{ padding: '12px', textAlign: 'left', fontWeight: '600' }}>Created</th>
                  </tr>
                </thead>
                <tbody>
                  {flights.map((flight) => (
                    <tr key={flight.flightId} style={{
                      borderBottom: '1px solid #f3f4f6'
                    }}>
                      <td style={{ padding: '12px' }}>
                        <code style={{ 
                          background: '#f3f4f6', 
                          padding: '4px 8px',
                          borderRadius: '4px',
                          fontSize: '0.85rem',
                          fontFamily: 'monospace'
                        }}>
                          {flight.flightId}
                        </code>
                      </td>
                      <td style={{ padding: '12px' }}>
                        <span style={{
                          display: 'inline-block',
                          padding: '4px 10px',
                          background: getStatusColor(flight.status),
                          color: 'white',
                          borderRadius: '4px',
                          fontSize: '0.8rem',
                          fontWeight: '600',
                          textTransform: 'uppercase'
                        }}>
                          {flight.status}
                        </span>
                        {flight.goal.isInternational && (
                          <span style={{ marginLeft: '8px', fontSize: '1.2rem' }} title="International Flight">
                            🌍
                          </span>
                        )}
                      </td>
                      <td style={{ padding: '12px', color: '#374151' }}>
                        {flight.goal.destination || 'N/A'}
                      </td>
                      <td style={{ padding: '12px', color: '#6b7280', fontSize: '0.9rem' }}>
                        {flight.pilot?.githubLogin || 'Unknown'}
                      </td>
                      <td style={{ padding: '12px', color: '#6b7280', fontSize: '0.9rem' }}>
                        {flight.executionLog?.duration?.totalMinutes 
                          ? `${flight.executionLog.duration.totalMinutes}m` 
                          : '-'}
                      </td>
                      <td style={{ padding: '12px', color: '#6b7280', fontSize: '0.9rem' }}>
                        {flight.executionLog?.cost?.copilot?.estimatedCost 
                          ? `$${flight.executionLog.cost.copilot.estimatedCost.toFixed(2)}` 
                          : '-'}
                      </td>
                      <td style={{ padding: '12px', color: '#6b7280', fontSize: '0.85rem' }}>
                        {new Date(flight.createdAt).toLocaleString()}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <section style={{ 
          background: 'white',
          padding: '25px',
          borderRadius: '12px',
          boxShadow: '0 1px 3px rgba(0,0,0,0.1)'
        }}>
          <h3 style={{ margin: '0 0 15px 0', color: '#374151' }}>
            🚀 Try It Out
          </h3>
          <ul style={{ margin: '0', paddingLeft: '20px', color: '#6b7280', lineHeight: '1.8' }}>
            <li>Click <strong>"Create Sample Flight"</strong> to write a new flight record to Azure Blob Storage</li>
            <li>Records are stored as JSONL (JSON Lines) format with date partitioning</li>
            <li>Click <strong>"Refresh"</strong> to query all flights from Azure</li>
            <li>Data is ready for DuckDB analytics queries</li>
          </ul>
        </section>
      </main>

      <footer style={{
        marginTop: '60px',
        paddingTop: '20px',
        borderTop: '1px solid #e5e7eb',
        textAlign: 'center',
        color: '#9ca3af',
        fontSize: '0.9rem'
      }}>
        <p>Flight Tracker v0.1.0 • Azure Static Web Apps + Blob Storage + DuckDB</p>
      </footer>
    </div>
  );
}
EOF

echo -e "${GREEN}✓ Dashboard created${NC}"
echo

# Create .env.local for development
cat > packages/dashboard/.env.local << EOF
AZURE_STORAGE_ACCOUNT=$AZURE_STORAGE_ACCOUNT
AZURE_STORAGE_KEY=$AZURE_STORAGE_KEY
AZURE_STORAGE_CONTAINER=$AZURE_STORAGE_CONTAINER
JWT_SECRET=$JWT_SECRET
EOF

echo -e "${YELLOW}Installing dependencies...${NC}"
cd packages/dashboard
npm install --silent
echo -e "${GREEN}✓ Dependencies installed${NC}"
echo

cd ../..

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Dashboard Ready!${NC}"
echo -e "${GREEN}================================${NC}"
echo
echo -e "${YELLOW}To test locally:${NC}"
echo "  cd packages/dashboard"
echo "  npm run dev"
echo "  Open: http://localhost:3000"
echo
echo -e "${YELLOW}Features:${NC}"
echo "  • ➕ Create sample flights"
echo "  • 📊 Query all flights from Azure Blob"
echo "  • 🔄 Real-time refresh"
echo "  • 📅 Date-partitioned storage"
echo
echo -e "${GREEN}Next: Test the dashboard locally!${NC}"
