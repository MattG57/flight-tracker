# Flight Data Structure

This package defines the core data structure for tracking AI agent execution "flights" with comprehensive telemetry and outcome data.

## Schema Version: 1.0.0

The flight data structure uses semantic versioning to support backwards compatibility as requirements evolve.

## Overview

The Flight data structure captures all aspects of an AI agent execution from planning through completion:

- **Flight Planning**: Goal definition (explicit or implied), destination type, complexity indicators
- **Pilot Information**: GitHub login and identity of who initiated the flight
- **Execution Telemetry (FDR)**: Duration, timeline events, rework tracking
- **Cost Tracking**: Copilot tokens/cost, GitHub Actions minutes, PRU (Plan Resource Units)
- **Status & Outcomes**: Current state, PR tracking, merge/deploy status, failure analysis
- **Manual Closeout**: Notes, lessons learned, and formal completion

## Core Concepts

### Flight Metaphor

The system uses an aviation metaphor to make tracking intuitive:

- **Flight**: A single AI agent execution attempt
- **Takeoff**: When execution begins
- **Turbulence**: Issues encountered during execution
- **Landing**: Completion (successful or emergency)
- **International Flight**: Complex, cross-cutting changes
- **Flight Data Recorder (FDR)**: Execution log with full telemetry

### Status Lifecycle

Flights progress through these states:

1. `not_started` - Planned but not yet begun
2. `running` - Currently executing
3. `pending` - Completed, PR created, awaiting review
4. `pending_successful` - PR approved, awaiting merge
5. `successful` - Merged and deployed
6. `churn` - Required rollback or significant rework after merge
7. `failure` - Did not complete successfully

### Goal Types

- **Explicit**: Flight plan was formally filed with clear objectives
- **Implied**: Goal was inferred from context without formal planning

## Dashboard Support

The schema is designed to support comprehensive dashboard analytics:

### Trend Analysis
- Flight frequency over time
- Popular destinations (bug-fix, feature, refactor, etc.)
- International flight success rates

### Success Metrics
- Overall success rate
- Progress/learning trends
- Time to completion

### Failure Analysis (Pareto)
- Failure categories with counts
- Common failure reasons
- Rework frequency

### Semantic Analysis
- Pattern recognition in successful flights
- Common factors in failures
- Lessons learned aggregation

## Files

- `schema/flight-v1.schema.json` - JSON Schema definition (machine-readable)
- `src/types.ts` - TypeScript type definitions
- `examples/` - Example flight data for reference:
  - `successful-flight.json` - Simple successful bug fix
  - `international-flight.json` - Complex feature with rework
  - `failed-flight.json` - Failed deployment with lessons learned

## Usage

### TypeScript

```typescript
import { Flight, FlightStatus, FlightGoal } from '@flight-tracker/core';

const flight: Flight = {
  schemaVersion: "1.0.0",
  flightId: "flight-001",
  goal: {
    type: "explicit",
    description: "Fix authentication bug",
    flightPlanFiled: true,
    destination: "bug-fix"
  },
  status: "running",
  createdAt: new Date().toISOString()
};
```

### JSON Validation

Use the JSON Schema file for validation:

```bash
# Using a JSON schema validator
ajv validate -s schema/flight-v1.schema.json -d examples/successful-flight.json
```

## Schema Evolution

The schema includes versioning to support backwards compatibility:

1. **schemaVersion** field tracks the version
2. **metadata** object allows flexible extensions
3. Optional fields enable gradual adoption
4. Future versions can add fields without breaking existing data

When schema changes are needed:
- Minor version bump (1.0.0 → 1.1.0): Add optional fields, maintain compatibility
- Major version bump (1.0.0 → 2.0.0): Breaking changes, requires migration

## Key Data Elements

### Required Fields
- `schemaVersion`: Version identifier
- `flightId`: Unique identifier (format: `flight-*`)
- `goal`: Flight objective and type
- `status`: Current state
- `createdAt`: Creation timestamp

### Recommended Fields
- `issueNumber`: GitHub issue reference
- `pilot.githubLogin`: Who initiated the flight
- `executionLog`: Telemetry and cost data
- `statusDetails`: PR numbers, failure reasons

### Dashboard-Critical Fields
- `goal.destination`: For "What destinations are popular?"
- `goal.isInternational`: For tracking complex changes
- `status`: For success rate calculation
- `statusDetails.failureCategory`: For Pareto analysis
- `executionLog.cost`: For cost tracking
- `executionLog.duration`: For efficiency metrics

## Contributing

When extending the schema:

1. Update `schema/flight-v1.schema.json` (or create v2 if breaking)
2. Update `src/types.ts` to match
3. Add example JSON demonstrating new fields
4. Update this README
5. Increment schema version appropriately

## License

MIT
