# Moderation operations

## Roles and access

- `support`: read the report queue and user-visible status.
- `moderator`: dismiss reports, remove content, and restrict accounts.
- `trust_safety_admin`: moderator capabilities plus suspension, restoration,
  and independent appeal review.

An active `moderation_operators/{uid}` assignment is authoritative. Custom
claims alone do not grant an operation. Operator assignments are provisioned
and revoked outside the client through reviewed administrative access.

## Intake and evidence

Report reasons use the allowlisted taxonomy: spam, harassment, hate, sexual
content, violence, self-harm, misinformation, privacy, and other. The server
verifies target existence and reporter visibility and captures a bounded
target snapshot. Do not copy unrelated private conversation into evidence.

## Response targets

- imminent violence/self-harm: acknowledge and escalate immediately;
- credible safety/privacy threats: initial review within four hours;
- harassment/hate/sexual content: initial review within 24 hours;
- spam/misinformation/other: initial review within 72 hours.

Emergency action may remove content or suspend an account, but still requires
a taxonomy, rationale, stable action ID, and immutable audit record.

## Actions, status, and appeals

Content actions can dismiss a report, remove an Insight/message/comment, or
archive a reported group. Account actions set user-visible `accountStatus` to active,
restricted, or suspended. Every decision creates one immutable
`moderation_audit/{actionId}` record and resolves the report idempotently.

Affected users may submit one appeal per action. A trust-and-safety reviewer
other than the original operator must review it. Appeal decisions create a
separate immutable audit record. Overturning restores account status; content
restoration requires a separate evidence-preserving operator action.

## Retention and privacy

- open/resolved reports and evidence: 180 days after resolution;
- moderation audit and appeal decisions: 24 months;
- debug logs: never include report details, invite tokens, contact data, or
  full faith-content bodies;
- access is least-privilege and reviewed quarterly;
- legal/safety holds override deletion only through a documented case owner
  and expiry date.

Operators should inspect only the evidence necessary for the reported target.
Exporting evidence outside the moderation system is prohibited.
