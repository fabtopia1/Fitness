# 04 — Security rules

Source: `firebase/firestore.rules`, `firebase/storage.rules`
Tests: `firebase/rules-test/firestore.rules.test.js` — **39 tests, all passing
against the real rules engine in the Firestore emulator.**

## 1. The five principles

1. **Deny by default.** The final `match /{document=**} { allow read, write: if false; }`
   is not a formality — it is what makes a collection created by hand in the
   console unreachable from a client.
2. **Ownership is one comparison.** Everything lives under `users/{uid}`, so
   `request.auth.uid == uid` is the whole authorisation model. There is no
   query a client can construct that spans two users.
3. **The collection name is an allow-list, not a wildcard.** Thirteen names.
   Adding a feature means adding a line, deliberately, in review.
4. **Deletes are refused everywhere.** The client soft-deletes by writing a
   `deletedAt` tombstone. A hard delete would be resurrected by another
   device's next pull.
5. **Validation is a backstop, not the primary check.** The client validates at
   entry. These rules exist for the case where the client is not ours.

## 2. Structure

```
match /users/{uid} {
  allow get, list:      if isOwner(uid);
  allow create, update: if isOwner(uid) && isValidProfile();
  allow delete:         if false;          // privileged, audited operation

  match /{collection}/{docId} {
    allow get, list:      if isOwner(uid) && isMvpCollection(collection);
    allow create, update: if isOwner(uid) && isValidDocument();
    allow delete:         if false;        // tombstones only
  }
}
match /{document=**} { allow read, write: if false; }
```

## 3. What `isValidDocument()` enforces

| Check | Why |
|---|---|
| `isMvpCollection(collection)` | a client bug that invents a collection cannot create an unbudgeted, unindexed tree under every user |
| `isIsoDate(updatedAt)` | conflict resolution depends on it; a missing or malformed value would make last-write-wins meaningless |
| `deletedAt` null or ISO | a tombstone that cannot be parsed is a record that never disappears |
| `id == docId` when present | a payload whose id disagrees with its path makes the local and remote copies diverge on the next pull |
| `keys().size() <= 64` | a record is a handful of fields; far past that is a bug or an attempt to use the database as free storage |
| bounded strings | `title` ≤ 500, `name` ≤ 300, `note`/`notes`/`description` ≤ 4 000, `location` ≤ 500 |
| bounded numbers | `kcal` ≤ 100 000, macros ≤ 10 000 g, `weightKg` ≤ 500, `quantityG` ≤ 100 000, `millilitres` ≤ 30 000, `hour` 0–23, `minute` 0–59 |

`isIsoDate` also bounds length to 20–32 characters, so a "date" field cannot
smuggle a megabyte.

## 4. What `isValidProfile()` enforces

Beyond the shared checks: `id == uid`, `email` ≤ 320 characters (RFC maximum),
`displayName` ≤ 120, `photoUrl` ≤ 2 048, and physiological bounds identical to
the ones the onboarding form applies — height 0–300 cm, weight 0–500 kg,
weekly rate 0–5 %, training days 0–14, calorie override 0–20 000.

A value outside those bounds would make every derived target meaningless, so
it is refused at both ends.

## 5. Storage

`firebase/storage.rules` denies everything.

The MVP uploads nothing. Progress photos — the most sensitive data in the
product — stay in the app's private directory. Not uploading them is a
stronger guarantee than any rule written here. The file exists so the bucket
is closed by default if it is ever provisioned, rather than inheriting a
permissive template.

## 6. The test suite

```bash
cd firebase/rules-test
npm ci
npm run emulator      # starts the Firestore emulator and runs vitest
```

39 tests in six groups:

| Group | Proves |
|---|---|
| ownership | anonymous reads and writes fail; a user reaches their own data; **a user cannot read or write another account** |
| the collection allow-list | each of the thirteen collections accepts a valid write and a read; an undeclared collection is refused for both |
| document shape | a write without `updatedAt` fails; a Firestore `Timestamp` in `updatedAt` fails; an `id` that disagrees with the path fails; a tombstone succeeds |
| input bounds | over-long titles and notes fail; an impossible bodyweight or energy value fails; an hour of 25 fails; an 80-field document fails |
| the profile document | a foreign `id` fails; impossible height and calorie override fail; an **empty** email succeeds, because local mode has none |
| deletes | a client cannot hard-delete a record or its own account document |

## 7. A defect these tests found

The rules written during the architecture phase required
`request.resource.data[field] is timestamp`. The offline write path serialises
to JSON for Hive and replays the identical map to Firestore, where dates are
ISO-8601 **strings**.

Every client write would have been rejected with `PERMISSION_DENIED`, in
production, on the first device that came back online — and because writes are
queued and retried in the background, the failure would have surfaced as
"nothing ever syncs" rather than as an error anyone could act on.

Reviewing rules by eye does not catch that. Executing them does.

## 8. Authentication guards in the app

Rules are the server-side half. The client half is the router redirect in
`app/lib/core/router/app_router.dart`, which is the single place that decides
where a user belongs:

```
auth still resolving           → splash (never flash sign-in at a signed-in user)
signed out                     → /welcome
signed in, not onboarded       → /onboarding
signed in, onboarded, on auth  → /home
```

Because it is a `redirect` rather than per-screen checks, there is no screen
that can be reached by a deep link without passing it.

Additionally, `AuthRepository.signOut()` wipes **every** local box. On a shared
device, leaving one account's training log in Hive for the next person to read
would be a serious privacy failure, so sign-out is destructive by design and
the confirmation dialog says so when writes are still queued.

## 9. Secret management

- No `google-services.json`, no `firebase_options.dart`, no keystore, no
  service-account key is committed. CI fails if any appears.
- Firebase configuration reaches the app exclusively through `--dart-define`
  at build time (`FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`,
  `FIREBASE_PROJECT_ID`, `FIREBASE_STORAGE_BUCKET`), supplied by CI from
  repository secrets.
- Release signing comes from `android/key.properties`, which is gitignored;
  without it the build falls back to the debug key so a fresh clone still
  builds.
- **No AI provider key exists anywhere in the app.** The AI Hub composes a
  prompt locally and hands it to the assistant the user already has. A key
  shipped inside an APK is a key that has been published.
