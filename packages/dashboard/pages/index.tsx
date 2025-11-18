import { useEffect, useState } from 'react';

export default function Home() {
  const [flights, setFlights] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    loadFlights();
  }, []);

  async function loadFlights() {
    try {
      setLoading(true);
      const res = await fetch('/api/flights-list');
      const data = await res.json();
      if (data.error) throw new Error(data.error);
      setFlights(data.flights);
      setError(null);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  async function createHelloWorldFlight() {
    try {
      setCreating(true);
      const flight = {
        schemaVersion: '1.0.0',
        flightId: `flight-hello-world-${Date.now()}`,
        status: 'successful',
        goal: {
          type: 'explicit',
          description: 'Hello World from Dashboard',
          destination: 'test'
        },
        pilot: {
          githubLogin: 'dashboard-user'
        },
        createdAt: new Date().toISOString()
      };

      const res = await fetch('/api/flights-create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(flight)
      });

      const data = await res.json();
      if (data.error) throw new Error(data.error);
      
      alert('Flight created successfully!');
      await loadFlights();
    } catch (err: any) {
      alert('Error: ' + err.message);
    } finally {
      setCreating(false);
    }
  }

  return (
    <div style={{ padding: '2rem', fontFamily: 'system-ui, sans-serif' }}>
      <h1>✈️ Flight Tracker - Hello World</h1>
      
      <div style={{ marginTop: '2rem', marginBottom: '2rem' }}>
        <button 
          onClick={createHelloWorldFlight}
          disabled={creating}
          style={{
            padding: '0.75rem 1.5rem',
            fontSize: '1rem',
            backgroundColor: '#0070f3',
            color: 'white',
            border: 'none',
            borderRadius: '5px',
            cursor: creating ? 'not-allowed' : 'pointer',
            opacity: creating ? 0.6 : 1
          }}
        >
          {creating ? 'Creating...' : '🛫 Create Hello World Flight'}
        </button>
      </div>

      <h2>📦 Flights in Storage</h2>
      
      {loading && <p>Loading...</p>}
      {error && <p style={{ color: 'red' }}>Error: {error}</p>}
      
      {!loading && !error && (
        <div>
          <p><strong>Total flights:</strong> {flights.length}</p>
          <ul style={{ listStyle: 'none', padding: 0 }}>
            {flights.map((flight, i) => (
              <li key={i} style={{ 
                padding: '0.5rem',
                marginBottom: '0.5rem',
                backgroundColor: '#f5f5f5',
                borderRadius: '3px'
              }}>
                📄 {flight.name} ({(flight.size / 1024).toFixed(2)} KB)
                <br />
                <small style={{ color: '#666' }}>
                  Last modified: {new Date(flight.lastModified).toLocaleString()}
                </small>
              </li>
            ))}
          </ul>
          {flights.length === 0 && <p>No flights yet. Create one!</p>}
        </div>
      )}
    </div>
  );
}
