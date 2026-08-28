# LifeDNA OS — Security & Privacy

**Version:** 1.0
**Owner:** Security — **sign-off is mandatory before any production release**

---

## 1. Position

LifeDNA OS holds the most sensitive category of personal data a consumer app can hold:
continuous physiology, body composition, eating behaviour, sleep, location-adjacent
calendar data and conversations about all of it. The commitments below are not marketing
language; each maps to an implemented control.

1. Health data is **never** used for advertising and is **never** sold.
2. Every third-party disclosure is enumerated in §7 and requires explicit consent.
3. The user can export everything and delete everything, and deletion is real.
4. We collect the minimum required for a stated product purpose.
5. Secrets never reach the client.

---

## 2. Data classification

| Class | Examples | Controls |
|---|---|---|
| **C1 — Critical** | Health records, sleep, body composition, photos, AI conversations | Encrypted at rest and in transit; per-user rules; never logged; never in analytics; export/delete on demand |
| **C2 — Sensitive** | Email, name, DOB, calendar events, tasks | Encrypted; per-user rules; never in analytics |
| **C3 — Internal** | Aggregated usage, funnels, error rates | Pseudonymous; hashed user id |
| **C4 — Public** | Exercise and food catalogues, app config | Read-only to authenticated users |

**Hard rule:** C1 and C2 never appear in a log line, an analytics event, a crash report, or
a support ticket attachment. Enforced by a redacting logger plus a unit test asserting the
redaction pattern.

---

## 3. Threat model

| # | Threat | Vector | Mitigation |
|---|---|---|---|
| T-01 | Another user reads my data | Forged uid in a request | Firestore rules enforce `request.auth.uid == uid` on every path; default deny; automated rules test suite |
| T-02 | Attacker extracts AI keys | Decompile the APK | No provider key exists in the client. All AI calls go through Cloud Functions with Secret Manager |
| T-03 | Attacker steals calendar access | Refresh token exfiltration | Refresh tokens live only in `_admin/oauth_tokens`, KMS-encrypted, no client read path |
| T-04 | Device theft | Physical access | Optional biometric app lock; SQLCipher-encrypted local database; keys in the platform keystore |
| T-05 | MITM | Hostile network | TLS 1.3 everywhere; certificate pinning on the LifeDNA API domain |
| T-06 | Abuse of expensive endpoints | Scripted AI calls | Per-user rate limits, daily token budgets, App Check attestation |
| T-07 | Malicious client writes | Direct SDK abuse | Rules restrict writable collections and immutable fields; server-derived documents are read-only |
| T-08 | Data leaked to an AI provider | Over-broad context | Minimized context (`docs/11 §4`), zero-retention contractual terms, per-conversation disable |
| T-09 | Insider access | Employee curiosity | Production access is break-glass, time-boxed, logged and reviewed; no standing access to user data |
| T-10 | Supply-chain compromise | Malicious dependency | Pinned versions, dependency audit in CI, review required for every new dependency |
| T-11 | Rules regression | A bad deploy | Rules are version-controlled and covered by an automated test suite in CI |
| T-12 | Export link leaked | Shared URL | Signed URLs expire in 24 h, are emailed rather than returned to the client, and are single-account scoped |

---

## 4. Authentication and authorization

| Control | Implementation |
|---|---|
| Identity | Firebase Auth: email/password, Google, Apple, Microsoft |
| Password policy | ≥ 10 characters, breach-checked; Firebase-managed hashing |
| Session | Firebase ID tokens, 1 h lifetime, transparent refresh |
| Re-authentication | Required for account deletion, email change, and disabling the app lock |
| App attestation | Firebase App Check (Play Integrity) on all callables |
| Authorization | Firestore rules only. No client-side authorization decision is trusted |
| Server privilege | Functions use the Admin SDK; every function scopes writes to the calling uid |

---

## 5. Encryption

| State | Control |
|---|---|
| In transit | TLS 1.3; certificate pinning for the API domain; cleartext traffic disabled in the manifest |
| At rest (cloud) | Google-managed encryption for Firestore and Storage |
| At rest (device) | SQLCipher for the Drift database; key in Android Keystore / iOS Keychain |
| Secrets | Secret Manager for provider keys; Cloud KMS envelope encryption for OAuth refresh tokens |
| Backups | Encrypted; same access controls as production |
| Key rotation | Provider API keys quarterly; KMS key versions annually with re-wrap |

---

## 6. Privacy by design

### 6.1 Minimization

| Not collected | Why |
|---|---|
| Precise location | No feature needs it |
| Contacts | No social features |
| Device identifiers beyond the FCM token | Not needed |
| Email content | Copilot reads summaries at request time; nothing is stored |
| Photo library beyond user-selected images | Scoped picker only |

### 6.2 Consent

Granular, logged, revocable, and each recorded with its version:

| Consent | Required for | Revocable |
|---|---|---|
| Health data processing | Recovery, sleep, activity features | Yes — data retained until deletion is requested |
| AI processing | Assistants, insights | Yes — deterministic features continue |
| Calendar access | Calendar module | Yes — token revoked at the provider |
| Analytics | Product improvement | Yes — opt-out honoured immediately |
| Photo storage | Progress photos | Yes — photos deleted on revocation |

Stored in `users/{uid}/settings/privacy.consents` with `type`, `grantedAt` and `version`.
A policy version bump re-prompts rather than assuming continuity.

### 6.3 Subject rights

| Right | Mechanism | SLA |
|---|---|---|
| Access | `exportData` (JSON + CSV) | Immediate (async build, minutes) |
| Portability | Same, machine-readable | Immediate |
| Rectification | Every value is editable in-app | Immediate |
| Erasure | `deleteAccount` with a real cascade | ≤ 30 days, confirmed by email |
| Restriction | Disable modules and processing individually | Immediate |
| Objection | Analytics opt-out; AI opt-out | Immediate |

### 6.4 Deletion cascade

```
deleteAccount
  1. users/{uid}.deletedAt set · auth user disabled · all sessions revoked
  2. accountPurge task enqueued
  3. Recursive delete of every users/{uid}/** subcollection
  4. Storage prefix users/{uid}/** deleted
  5. OAuth tokens revoked AT THE PROVIDER, then deleted locally
  6. FCM tokens deleted
  7. Analytics deletion request issued for the pseudonymous id
  8. Audit record written containing NO personal data
  9. Confirmation email sent
```

Verified by test `INT-05`, which asserts zero remaining documents across every known path.

---

## 7. Third-party disclosures

| Recipient | Data | Purpose | Legal basis | Retention |
|---|---|---|---|---|
| Google Firebase | All app data | Hosting, auth, storage | Contract (processor) | Until deletion |
| Anthropic | Minimized context + message text | AI responses | Consent | Zero-retention terms required |
| Microsoft | Graph tokens, calendar/mail queries | Calendar and Copilot features | Consent | Per Microsoft terms |
| Google Calendar | OAuth tokens, event data | Calendar sync | Consent | Until disconnect |
| Open Food Facts | Barcode strings only | Food lookup | Legitimate interest | N/A — no user data sent |
| Crashlytics | Stack traces (redacted) | Stability | Legitimate interest | 90 days |

**Open Food Facts receives only a barcode number.** No user identifier, no context.

---

## 8. Health-specific compliance

| Requirement | Status |
|---|---|
| Google Play Health apps policy | Declaration completed in Sprint 8; all health claims legally reviewed |
| Health Connect data-use policy | Data used only for the declared purposes; no advertising; no sale; no unrelated sharing |
| Not a medical device | Explicit in-app disclaimer; no diagnosis, treatment or clinical claims; reviewed by legal |
| Safety floors | Calorie minimums, deficit caps and rate ceilings enforced in the engine, not just the UI |
| AI safety | Medical, disordered-eating, PED and self-harm interceptors; 100 % suite pass required |
| Age | Under-18 accounts not permitted in v1 |

**Disclaimer text (in-app, at onboarding and in Settings):**

> LifeDNA OS provides training, nutrition and lifestyle information for healthy adults. It
> is not a medical device and does not diagnose, treat, cure or prevent any condition.
> Consult a qualified healthcare professional before making significant changes to your
> diet or exercise, and immediately if you experience concerning symptoms.

---

## 9. Secure development

| Practice | Implementation |
|---|---|
| Code review | Every PR; security-labelled changes require a second reviewer |
| SAST | Runs on every PR; high-severity findings block merge |
| Dependency scanning | Every PR + weekly scheduled scan |
| Secret scanning | Pre-commit hook + CI; a committed secret fails the build and triggers rotation |
| Penetration test | Before v1.0 launch and annually thereafter |
| Rules testing | Automated suite asserting deny-by-default and cross-user isolation |
| Threat modelling | At design time for every new integration |

**Never committed:** `google-services.json`, `GoogleService-Info.plist`,
`firebase_options.dart`, `functions/.env`, service account keys, signing keystores. All are
in `.gitignore` and covered by secret scanning.

---

## 10. Incident response

| Phase | Actions | Owner |
|---|---|---|
| **Detect** | Automated alerts, user reports, researcher disclosure | On-call |
| **Triage** (≤ 1 h) | Classify severity, assess scope, open an incident channel | Security Lead |
| **Contain** (≤ 4 h) | Revoke credentials, disable the affected surface via kill switch, block the vector | Engineering |
| **Eradicate** | Patch, rotate every potentially exposed secret, verify | Engineering |
| **Notify** (≤ 72 h if personal data is affected) | Regulator and affected users, with specifics | Legal + Product |
| **Review** (≤ 7 days) | Blameless post-mortem; controls added; tests written | Whole team |

A `SECURITY.md` publishes a disclosure address and a 90-day coordinated-disclosure policy.

---

## 11. Retention

| Data | Retention | Then |
|---|---|---|
| Account and health data | Until deletion is requested | Full cascade purge |
| Raw `health_records` | 400 days | Compacted into `daily_stats`, raw deleted |
| AI conversations | 12 months of inactivity | Archived, then purged |
| Notification history | 30 days | Deleted |
| Crash reports | 90 days | Deleted |
| Analytics events | 14 months | Aggregated only |
| Audit logs | 24 months | Deleted (contain no personal data) |
| Backups | 30 days rolling | Overwritten |

---

## 12. Pre-launch security checklist

- [ ] Firestore rules deny by default and pass the automated isolation suite
- [ ] Storage rules restrict to `users/{uid}/**` with type and size limits
- [ ] No secret in any client artifact (verified by APK inspection)
- [ ] App Check enforced on every callable
- [ ] Rate limits enforced and load-tested
- [ ] Certificate pinning active with a documented rotation plan
- [ ] Local database encryption verified on a rooted device
- [ ] Deletion cascade verified end to end
- [ ] Export contains only the requesting user's data
- [ ] Penetration test complete with all high findings remediated
- [ ] Privacy policy, terms and health disclaimer published and linked in-app
- [ ] Play health-data declaration approved
- [ ] Logger redaction test passing
- [ ] AI safety suite at 100 %
- [ ] Incident response runbook rehearsed
