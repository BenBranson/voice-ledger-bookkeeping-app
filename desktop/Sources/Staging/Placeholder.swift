/// /staging — deferred.
///
/// Design is complete: docs/phase-0/10_STAGING_APPROVAL_AUDIT.md. Not part of
/// the approved Phase 1 scope (steps 1.0–1.2 only). The catalog this module
/// will eventually call into is being built read-only first, in `backend/` —
/// see docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.4. No write operation
/// exists yet for staging to stage.
public enum StagingPlaceholder {}
