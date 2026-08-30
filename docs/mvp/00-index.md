# LifeDNA OS — MVP delivery documents

These sixteen documents describe **what was built**, not what was designed.
`docs/01`–`docs/20` are the full-product design from the architecture phase;
they describe a fifteen-module system. This folder covers the nine-module MVP
that exists in `app/`, runs today, and is covered by 556 automated checks.

Where the two disagree, this folder is authoritative for the MVP.

| # | Document | Answers |
|---|---|---|
| 01 | [Product architecture](01-product-architecture.md) | How the app is put together and why |
| 02 | [Folder structure](02-folder-structure.md) | Where every file lives |
| 03 | [Firestore schema](03-firestore-schema.md) | What is stored, where, and how it is indexed |
| 04 | [Security rules](04-security-rules.md) | What stops one user reading another's data |
| 05 | [UI sitemap](05-ui-sitemap.md) | Every screen and how it is reached |
| 06 | [User flows](06-user-flows.md) | The journeys, as diagrams |
| 07 | [Sprint plan](07-sprint-plan.md) | The order the work was done, and what is next |
| 08 | [CI/CD](08-cicd.md) | What runs on every push and what gates a release |
| 09 | [Testing strategy](09-testing-strategy.md) | What is tested, how, and what is not |
| 10 | [MVP completion checklist](10-mvp-completion-checklist.md) | Feature-by-feature status |
| 11 | [Build checklist](11-build-checklist.md) | Producing an installable artefact |
| 12 | [Launch checklist](12-launch-checklist.md) | Store submission and beta rollout |
| 13 | [Risk assessment](13-risk-assessment.md) | What could go wrong, and the mitigation |
| 14 | [Technical debt log](14-technical-debt.md) | Everything knowingly left undone |
| 15 | [Production readiness](15-production-readiness.md) | Ship / do-not-ship, with evidence |
| 16 | [Architecture audit](16-architecture-audit.md) | Every issue found that could stop the app building, deploying, syncing, or scaling to 10 000 users |
| 17 | [Launch readiness audit](17-launch-readiness-audit.md) | Android build, Gradle, Firebase, Play, security, performance, memory, sync — plus the beta release checklist |
| 18 | [Google auth verification](18-google-auth-verification.md) | Why sign-in returned no ID token, per-flavour OAuth setup, and the device checklist that proves it works |
| 19 | [Build validation report](19-build-validation-report.md) | Toolchain compatibility, Gradle, signing, R8 and manifest — what is settled statically, by CI, and only on hardware |
| 20 | [Device validation scripts](20-device-validation-scripts.md) | Twelve scripts a tester runs on a physical Samsung device before the beta opens |
| 21 | [Closed beta certification](21-closed-beta-certification.md) | The remediation's verdict, scores, and the conditions of release |
| 22 | [Encrypted data migration](22-encrypted-data-migration.md) | How installs predating the encryption marker are migrated without losing data |
| 23 | [Android test protocol](23-android-test-protocol.md) | How device testing is run, recorded, and escalated |
| 24 | [Release verification matrix](24-release-verification-matrix.md) | Every claim, its evidence, and whether that evidence exists today |
| 25 | [Play internal testing](25-play-internal-testing.md) | The 48-hour critical path to 50 testers |
| 26 | [Samsung device checklist](26-samsung-device-checklist.md) | One UI behaviour that breaks exactly what this app depends on |
| 27 | [Firebase production deployment](27-firebase-production-deployment.md) | Everything that must exist in the console before a build |
| 28 | [Release sign-off](28-release-signoff.md) | C-1 re-verification, every remaining blocker, and the go/no-go |
| 29 | [Personal APK guide](29-personal-apk-guide.md) | Build, sign, install and update the app on your own phone — no Firebase, no Play Store |
| 30 | [Personal device checklist](30-personal-device-checklist.md) | One afternoon of testing on one phone, local mode only |
| 31 | [Personal release certification](31-personal-release-certification.md) | Final audit, scores, and the recommendation to install |
| 32 | [Build commands](32-build-commands.md) | Every command, its expected output, and what each failure means |
| 33 | [Final release audit](33-final-release-audit.md) | The Android-file audit: two critical blockers found and fixed |
| 34 | [Personal release certification](34-personal-release-certification-v2.md) | The current verdict, scores and the final APK checklist — supersedes 31 |

## The MVP in one paragraph

A Flutter application with an **offline-first architecture**: every write
commits to an encrypted local Hive database first, is queued in a durable
outbox, and only then replicates to Firestore. Reads never touch the network.
The app is fully usable with **no Firebase project configured at all** — that
is a supported mode, not a debug hatch. Nine modules ship: authentication,
dashboard, nutrition, supplements, workouts (including Live Gym Mode),
body tracking, calendar/tasks/reminders, health sync, and an on-device AI
coach.

## What is deliberately absent

Galaxy Fit 3 Bluetooth, the FitnessDNA prediction engine, machine learning,
predictive analytics, voice assistants, social features, a marketplace,
subscriptions, and gamification. Each is in `docs/20-future-expansion.md`.
None has a stub, a placeholder screen, or a disabled button in the shipped
app — a feature is either complete or absent.
