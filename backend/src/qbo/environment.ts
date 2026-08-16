/**
 * docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.8: "Environment is a property
 * of the connection record, resolved from the realmId at connect time and
 * immutable thereafter — never a global mode flag that could be wrong."
 */

import type { Environment } from "../config.js";

const SANDBOX_API_BASE_URL = "https://sandbox-quickbooks.api.intuit.com";
const PRODUCTION_API_BASE_URL = "https://quickbooks.api.intuit.com";

/**
 * Exactly one call site decides sandbox vs. production hostname. Any code
 * that needs to reach the QBO Accounting API goes through this function
 * rather than constructing a URL itself, so there is one place to fix if
 * the Wave 0 spike (docs/phase-0/SPIKE_QUEUE.md) finds this assumption wrong.
 */
export function resolveApiBaseUrl(environment: Environment): string {
  return environment === "production" ? PRODUCTION_API_BASE_URL : SANDBOX_API_BASE_URL;
}
