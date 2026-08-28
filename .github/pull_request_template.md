## What changed

<!-- One paragraph. What does this do, and why now? -->

## Scope

- [ ] Client (`app/`)
- [ ] Backend (`functions/`)
- [ ] Rules / indexes (`firebase/`)
- [ ] Documentation (`docs/`)

## Definition of done (docs/16 §11)

- [ ] Unit tests for domain and data changes; widget tests for new UI
- [ ] **Engine changes include fixtures passing in BOTH Dart and TypeScript**
- [ ] Acceptance criteria met, verified by someone other than the author
- [ ] Offline behaviour verified where this touches a user write
- [ ] Accessibility: TalkBack labels, 48 dp targets (64 dp in Live Gym), 200 % text
- [ ] Analytics events emitted per `docs/15` — and carrying no health values
- [ ] No new lint warnings; `tool/check_sources.py` passes
- [ ] Strings externalized
- [ ] `docs/03` or `docs/09` updated if a contract changed

## Safety

- [ ] No health value, food name, or message content reaches a log or an analytics event
- [ ] Any new recommendation is produced by a deterministic engine, not by a model
- [ ] Any new user-facing number is reproducible from stored inputs
