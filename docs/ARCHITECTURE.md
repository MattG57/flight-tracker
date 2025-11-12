# Architecture

## Data Lifecycle Strategy

### Pilot Phase (Current)
- **Storage**: SQLite database (file-based)
- **Location**: `./data/flights.db` in project root
- **Dashboard**: Local Next.js/React app reading directly from SQLite
- **Deployment**: Run locally, no hosting needed

### Advantages of this approach:
- Zero infrastructure setup
- Fast iteration
- No hosting costs
- Data persists locally
- Easy backup (just copy .db file)

### Future Scaling Path

When ready to scale beyond pilot:

1. **Database Migration**
   - SQLite → PostgreSQL (or MongoDB for flexible schema)
   - Use Prisma/TypeORM for smooth migration
   - Host on: Railway, Supabase, or Neon

2. **Dashboard Hosting Options**
   - **Option A**: Vercel/Netlify (recommended)
     - Deploy dashboard as static site + API routes
     - Free tier sufficient for pilot scale
   - **Option B**: Docker container
     - Package dashboard + API + DB
     - Deploy to Railway, Render, or Fly.io
   - **Option C**: GitHub Pages + Serverless
     - Static dashboard on GH Pages
     - API on AWS Lambda/Cloudflare Workers

3. **Data Pipeline** (if needed)
   - Add event streaming (e.g., webhook → queue → DB)
   - Separate write path from read path

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

## Technology Choices (To Be Decided)

- **Dashboard Framework**: Next.js vs. Vite+React
- **ORM**: Prisma vs. Drizzle vs. raw SQL
- **Charts**: Recharts vs. Chart.js vs. D3
- **UI**: shadcn/ui vs. MUI vs. custom

Next steps: Define the Flight data schema in `packages/core`
