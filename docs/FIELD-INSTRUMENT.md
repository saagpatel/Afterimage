# Field Instrument Contract

This document describes the confidence-bearing slice implemented in the current working tree. It is a product and engineering contract, not a claim that Afterimage has been validated in natural field use.

## User flow

1. **Orient.** Capture a current view or select a photo and establish a usable location. A heading is helpful but optional evidence.
2. **Inspect.** Review up to five nearby archive candidates. Candidate identity, date, distance, and disposition stay visible.
3. **Compare or refuse.** A draggable overlay appears only for a `confident` candidate with an available historical image. Every other disposition withholds the overlay and names the leading reason.
4. **Adjust.** Move the historical image horizontally or vertically and adjust scale. Alignment is a presentation adjustment; it never feeds back into confidence.
5. **Review provenance.** Inspect a compact archive summary, distinguish rights-link presence from verification, and expand technical lineage details when needed. The local index ID is labeled as distinct from a source record ID, and unstored values remain explicitly unavailable.
6. **Save locally.** Render the current reveal/alignment as a PNG in the app's protected Application Support container. It is not added to Photos or uploaded.
7. **Share deliberately.** A separate system share sheet lets the user choose whether and where to export a copy.

## Domain boundary

`MatchEvidence` stores observations. `MatchConfidenceEngine` applies policy. `MatchExplanationPresenter` converts the decision into user-facing language. Presentation code does not calculate confidence, and alignment controls cannot make a candidate more confident.

`HistoricalAssetProvenance` is a no-rebuild compatibility layer over the current unversioned bundled database. It preserves the local index record ID and the stored archive-heading metadata confidence when a heading exists. Source-record URL, ingestion version, coordinate origin, and coordinate/date/rights confidence are typed unavailable states. Afterimage does not derive those values from IDs, URLs, or field presence. The field UI summarizes incomplete lineage and keeps the detailed audit rows in a collapsed disclosure.

The currently modeled signals are:

- location distance plus the observed horizontal-accuracy bound;
- conservative heading-difference upper bound when the current compass accuracy is usable and the archive direction has medium or high confidence;
- archive date availability;
- attribution and rights-record availability;
- historical display-image availability;
- raw, absolute Vision feature-print distance;
- correlated/duplicate archive-record group size.

Missing signals remain missing. Candidate values are never min/max-normalized against the other results in the current query.
Invalid, negative, non-finite, or out-of-range numeric observations are treated as missing evidence; they never become support.
Low-confidence archive headings remain missing evidence. For usable headings, the engine adds the current compass accuracy radius to the raw angular difference before scoring, so an imprecise bearing cannot masquerade as strong viewpoint support.

## Dispositions and overlay policy

| Disposition | Meaning | Overlay |
|---|---|---|
| `confident` | At least two independent signals support the candidate, archive display/provenance basics exist, and the absolute confidence threshold is met without a strong contradiction. | Allowed |
| `uncertain` | A candidate exists, but the available support does not meet the refusal threshold. | Withheld |
| `insufficientEvidence` | Too few independent signals exist, or required archive display/attribution evidence is absent. | Withheld |
| `conflictingSignals` | Strong supporting and strong contradictory evidence coexist. | Withheld |
| `unavailableLocation` | A usable location was not available. | Withheld |
| `noMatch` | No archive candidate exists inside the supported search path. | Withheld |

The current engine uses inspectable absolute bands for distance, conservative heading-difference upper bound, and Vision distance. Archive deficiencies cap the decision. The internal `fixtureEstimatedProbability` exists only to measure the frozen policy-regression corpus; the product UI does not present it as a real-world probability.

## Deterministic evidence

`AfterimageTests/Fixtures/match-confidence-v1.json` freezes 13 cases spanning true matches, near misses, wrong location, wrong heading, degraded images, missing metadata, duplicates, conflicts, unavailable location, no match, and location-only insufficiency.

The toolchain-light verifier compiles the exact production confidence source, executes adversarial non-finite/negative evidence checks, and reports explicitly fixture-prefixed Brier score and calibration error plus refusal recall and disposition accuracy. These are internal consistency measures over independently labeled synthetic scenarios, not efficacy estimates. Debug launch arguments use generated local images and do not access Camera, Photos, location history, or archive hosts:

`scripts/benchmark-match-confidence.swift` exercises the same production engine at high volume. It measures only confidence-policy cost, not Vision, camera, overlay rendering, app memory, or energy.

- `--afterimage-demo-comparison`
- `--afterimage-demo-uncertain`
- `--afterimage-demo-conflict`
- `--afterimage-demo-insufficient`
- `--afterimage-demo-unavailable-location`
- `--afterimage-demo-no-match`
- `--afterimage-demo-cities`

## Privacy and data behavior

- Matching uses the bundled metadata index and on-device computation.
- User photos, location, and heading are not sent to an Afterimage service.
- Historical images are not bundled in full; uncached thumbnails are requested directly from archive hosts.
- The in-flow disclosure distinguishes on-device matching from those ordinary archive-host image requests; captured photos and precise locations are not included in the request.
- Automated verification uses only project-owned fixtures and generated images.
- Local pairs use the iOS complete file-protection class in the app container and are unavailable while the device is locked.
- Sharing is a distinct user action through the system share sheet.

## Claim ceiling

Passing fixtures proves deterministic behavior for those fixtures. Simulator proof establishes only the exercised build, UI, and accessibility surfaces. Device field proof is separately required for camera, live location/heading, real archive retrieval, natural walking use, and real-world match calibration. See `LIMITATIONS.md`.
