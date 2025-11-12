/**
 * Flight Tracker Core Types
 * 
 * TypeScript types for tracking AI agent execution flights.
 * Based on schema version 1.0.0
 */

/**
 * Schema version for backwards compatibility
 */
export type SchemaVersion = "1.0.0";

/**
 * Flight status enum representing the current state of a flight
 */
export type FlightStatus = 
  | "not_started"   // Flight planned but not yet started
  | "running"       // Flight currently in progress
  | "pending"       // Flight completed, awaiting PR review
  | "pending_successful" // PR approved, pending merge
  | "successful"    // Successfully completed and deployed
  | "churn"         // Changes required rework/rollback
  | "failure";      // Flight failed

/**
 * Goal type - explicit (flight plan filed) or implied
 */
export type GoalType = "explicit" | "implied";

/**
 * Failure category for Pareto analysis
 */
export type FailureCategory =
  | "requirements_unclear"
  | "technical_complexity"
  | "build_failure"
  | "test_failure"
  | "deployment_failure"
  | "timeout"
  | "resource_constraint"
  | "external_dependency"
  | "other";

/**
 * Information about the pilot (person) who initiated the flight
 */
export interface Pilot {
  /** GitHub username of the pilot */
  githubLogin: string;
  /** Optional display name */
  displayName?: string;
}

/**
 * Flight goal/scope/objective
 */
export interface FlightGoal {
  /** Whether the goal was explicit (flight plan filed) or implied */
  type: GoalType;
  /** Description of the flight objective */
  description?: string;
  /** Whether a formal flight plan was filed */
  flightPlanFiled?: boolean;
  /** What destination/outcome is targeted (e.g., 'bug-fix', 'feature', 'refactor') */
  destination?: string;
  /** Whether this is an 'international flight' - complex/cross-cutting changes */
  isInternational?: boolean;
}

/**
 * Duration metrics for the flight
 */
export interface Duration {
  /** When the flight started (ISO 8601) */
  startTime?: string;
  /** When the flight ended (ISO 8601) */
  endTime?: string;
  /** Total duration in minutes */
  totalMinutes?: number;
}

/**
 * GitHub Copilot cost tracking
 */
export interface CopilotCost {
  /** Total tokens used */
  tokens?: number;
  /** Estimated cost in USD */
  estimatedCost?: number;
}

/**
 * Cost tracking for the flight
 */
export interface Cost {
  /** GitHub Copilot costs */
  copilot?: CopilotCost;
  /** GitHub Actions minutes consumed */
  actionsMinutes?: number;
  /** PRU (Plan Resource Units) cost - custom metric */
  pruCost?: number;
}

/**
 * Execution event in the flight timeline
 */
export interface ExecutionEvent {
  /** When the event occurred (ISO 8601) */
  timestamp: string;
  /** Event type (e.g., 'takeoff', 'turbulence', 'landing') */
  type: string;
  /** Event details */
  message?: string;
  /** Additional event-specific data */
  metadata?: Record<string, any>;
}

/**
 * Flight Data Recorder (FDR) - Log of execution telemetry
 */
export interface ExecutionLog {
  /** Duration metrics */
  duration?: Duration;
  /** Cost tracking */
  cost?: Cost;
  /** Whether rework was required during execution */
  reworkRequired?: boolean;
  /** Number of times rework was needed */
  reworkCount?: number;
  /** Timeline of execution events */
  events?: ExecutionEvent[];
}

/**
 * Additional status-specific information
 */
export interface StatusDetails {
  /** Pull request number if status is pending/successful */
  prNumber?: number;
  /** Whether the PR was merged */
  merged?: boolean;
  /** Whether changes were deployed */
  deployed?: boolean;
  /** Whether changes required churn/rollback */
  churned?: boolean;
  /** Reason for churn if applicable */
  churnReason?: string;
  /** Reason for failure if status is failure */
  failureReason?: string;
  /** Category of failure for Pareto analysis */
  failureCategory?: FailureCategory;
}

/**
 * Manual close-out of the flight plan
 */
export interface ManualCloseout {
  /** GitHub login of who closed the flight */
  closedBy?: string;
  /** When the flight was manually closed (ISO 8601) */
  closedAt?: string;
  /** Close-out notes */
  notes?: string;
  /** Key lessons learned from this flight */
  lessonsLearned?: string;
}

/**
 * Complete Flight record
 * 
 * Represents a single AI agent execution "flight" with comprehensive
 * tracking of goals, execution telemetry, costs, and outcomes.
 */
export interface Flight {
  /** Schema version for backwards compatibility */
  schemaVersion: SchemaVersion;
  /** Unique identifier for the flight */
  flightId: string;
  /** GitHub issue number associated with this flight */
  issueNumber?: number;
  /** Information about who initiated/piloted the flight */
  pilot?: Pilot;
  /** Flight Goal/Scope/Objective */
  goal: FlightGoal;
  /** Flight Data Recorder (FDR) - Log of execution telemetry */
  executionLog?: ExecutionLog;
  /** Current flight status */
  status: FlightStatus;
  /** Additional status-specific information */
  statusDetails?: StatusDetails;
  /** Manual close-out of the flight plan */
  manualCloseout?: ManualCloseout;
  /** When the flight record was created (ISO 8601) */
  createdAt: string;
  /** When the flight record was last updated (ISO 8601) */
  updatedAt?: string;
  /** Additional flexible metadata for future extensions */
  metadata?: Record<string, any>;
}
