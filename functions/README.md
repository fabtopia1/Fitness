# LifeDNA OS — Cloud Functions

Node 20 · TypeScript 5.5 · Firebase Functions v2 · region `europe-west1`

---

## 1. Why this tier exists

Firestore is the datastore and the client talks to it directly. This tier
therefore exists for exactly four reasons, and code that serves none of them
does not belong here:

1. **Secret custody** — AI provider keys, OAuth client secrets, refresh tokens.
2. **Cross-document computation** — rollups, engines, reports.
3. **Third-party mediation** — calendar sync, food lookup, push delivery.
4. **Trust boundaries** — anything the client must not be able to forge: token
   budgets, subscription state, account deletion.

Full inventory and operational parameters: `docs/08-backend-architecture.md`.

---

## 2. What is implemented

| Path | Status |
|---|---|
| `src/engines/nutrition/macroCalculator.ts` | **Complete** — the authoritative macro engine, parity-tested |
| `src/engines/recovery/recoveryEngine.ts` | **Complete** — the authoritative recovery engine, parity-tested |
| `src/lib/rounding.ts` | **Complete** — cross-language rounding (see §4) |
| `src/lib/errors.ts` | **Complete** — the stable `reason` registry from `docs/09 §1.2` |
| `src/lib/logger.ts` | **Complete** — structured logging that *refuses* to log a sensitive field |
| `src/triggers/onNutritionLogWrite.ts` | **Complete** — the daily rollup, written to be idempotent |
| Everything else | Contracts fixed in `docs/09`; scheduled by sprint in `src/index.ts` |

---

## 3. Engine parity

`src/engines/**` is mirrored by `app/lib/core/engines/**`. Both run the shared
fixtures in `../test/fixtures/engines/`, and a divergence fails both builds.

```bash
npm test                                   # includes the parity suite
python3 ../tool/generate_engine_fixtures.py   # regenerate after a formula change
```

The fixture generator is a deliberately independent third implementation of the
formulas in `docs/01 §6.2` and `docs/12`. Agreement between three
implementations written against the specification is far stronger evidence than
agreement between two written by the same hand — and it is how the bug in §4 was
found.

---

## 4. Rounding is not a detail

`Math.round` rounds half toward +Infinity. Dart's `num.round()` rounds half
**away from zero**. They agree on positive halves and disagree on negative ones:

```
Math.round(-67.5)  === -67
(-67.5).round()    === -68     // Dart
```

`projectedWeeklyChangeKg` is negative for every user in a deficit. A value
landing on a `.5` boundary would have produced a different stored target on the
server than the client had already shown the user — a silent, intermittent,
nearly unreproducible inconsistency in a number people plan their diet around.

`src/lib/rounding.ts` removes the class of bug. **Do not call `Math.round`
inside `src/engines`.**

---

## 5. Idempotency

Firestore triggers are at-least-once, and Cloud Tasks retries. Every handler
here is written to tolerate being invoked twice:

| Surface | Mechanism |
|---|---|
| Rollups | Recomputed from source, never incremented |
| Health records | Document id is `sha256(source\|type\|startMs\|endMs)` |
| Sets, nutrition entries | Client-generated UUID v7 as the document id |
| Insights | Document id is `sha256(uid\|rule\|windowStart\|windowEnd)` |
| Reports | Document id is the period (`weekly_2026-W35`) |
| Callables | Client `requestId`, cached response, 5-minute TTL |

Assuming exactly-once delivery is the most common source of production data
corruption in a Firestore backend. It is assumed nowhere in this codebase.

---

## 6. Local development

```bash
npm install
npm run build
npm run serve          # functions + firestore + auth emulators

# From the repository root, for the full suite with seeded data:
firebase emulators:start --import=./firebase/seed --export-on-exit
```

Set `AI_PROVIDER=fake` in the emulator (it is the default in `.env.example`)
so tests return deterministic fixtures and never spend tokens.

---

## 7. Configuration

Copy `.env.example` to `.env` for local work. **In production these are Secret
Manager secrets bound to individual functions**, not a file — see
`docs/19-security-privacy.md §5`.

Nothing in that file may ever reach the client. An API key in an APK is
extractable in minutes, which is the entire reason the AI tier is server-side
(`docs/19 §3`, threat T-02).

---

## 8. Deployment

```bash
firebase use staging && firebase deploy --only functions
firebase deploy --only functions:onNutritionLogWrite    # single function
```

**Deploy rules and indexes before the client release that needs them.** A
composite index takes minutes to build; shipping both together causes a
production outage on whichever screen runs the query.

Rollback: `firebase functions:rollback`. Client-side, every Phase 2/3 module
has a Remote Config kill switch.
