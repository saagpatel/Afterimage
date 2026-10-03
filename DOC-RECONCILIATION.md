# Documentation Reconciliation

Updated: 2026-08-30

This reconciliation is bound to the uncertainty-aware field-walk working tree based on `488e271d8106ef3ca961484e24574635d0df4174`. Runtime claims remain bounded by `docs/LIMITATIONS.md`.

## Reconciled claims

| Surface | Prior drift | Current wording |
|---|---|---|
| Product identity | Presented a best-match overlay as if it identified the historical view. | Describes candidates, evidence, uncertainty, and refusal. |
| Scoring | Claimed a 70/30 composite and “Strong Match.” | Documents typed evidence and absolute refusal thresholds; no user-facing real-world percentage. |
| Offline behavior | Implied the full experience was offline. | Separates bundled metadata/local fixtures from remote archive-image retrieval. |
| City coverage | Claimed six covered cities. | States live bundled counts for NYC, Chicago, and San Francisco; zero-record cities are disabled. |
| Heading | Described hard filtering and fallback. | Documents annotation that preserves missing/contradictory evidence. |
| Gallery browse | Implied a placeholder image could support visual similarity. | Documents archive-browse mode without placeholder Vision ranking. |
| Field flow | Described an older comparison screen. | Documents orient, candidate inspection, gated compare/refusal, alignment, provenance, local save, and deliberate share. |
| Provenance lineage | Treated attribution and a rights URL as sufficient provenance. | Separates archive details from audit lineage, labels the local index ID, preserves stored heading metadata confidence, and marks unstored lineage unavailable without synthesis. |
| Privacy | Said no data leaves the phone without qualification. | Distinguishes on-device matching, archive-host requests, app-local saves, and user-chosen share destinations. |
| Readiness | Used earlier build/screenshot evidence as current. | Names the 2026-08-30 missing-Xcode/storage blocker and keeps build/runtime/performance status `UNKNOWN`. |
| App Store | Contained unsupported real-time, exact-location, six-city, fully-offline, and ready-to-submit claims. | Replaced with a non-publishable truthful draft and explicit pre-submission gates. |

## Current documentation map

- `README.md` — concise product and evidence boundary
- `CLAUDE.md` — repository implementation contract
- `IMPLEMENTATION-ROADMAP.md` — current architecture, completed slice, and remaining gates
- `docs/FIELD-INSTRUMENT.md` — evidence/refusal/flow contract
- `docs/RUNNABLE-PROOF.md` — exact verification commands and proof expectations
- `docs/LIMITATIONS.md` — explicit limitation ledger and unblock condition
- `PRIVACY.md` — runtime network, protected local save, and deliberate share behavior
- `APPSTORE-METADATA.md` — draft only; prohibited claims and submission gates

## Claim status

- Deterministic confidence/refusal fixture behavior: locally verified.
- Data-pipeline safety tests and bundled DB inspection: locally verified.
- Typed provenance compatibility and no-synthesis behavior: locally verified.
- Full iOS compilation and XCTest: `UNKNOWN` for this working tree.
- Simulator rendering and accessibility: `UNKNOWN` for this working tree.
- Camera/field matching, performance, memory, energy, and user comprehension: `UNKNOWN`.
- Publication, deployment, App Store readiness, and general matching efficacy: not claimed and not authorized.
