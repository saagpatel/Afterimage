# Afterimage Implementation Roadmap

Updated: 2026-08-30

## Product direction

Afterimage is being evolved from a best-match overlay demo into an uncertainty-aware historical field instrument. The product should explain what record might match, which evidence supports or contradicts it, and when a visually polished overlay would overstate the evidence.

## Current architecture

```text
camera / selected photo
        + location accuracy
        + optional heading accuracy
                  │
                  ▼
bundled read-only SQLite metadata ── SpatialQuery (100 m, then 500 m fallback)
                  │
                  ▼
MatchCandidate + typed MatchEvidence
  ├─ heading annotation (contradictions retained)
  ├─ archive thumbnail/cache result (missing image retained)
  ├─ absolute Vision feature distance for field matching
  ├─ archive metadata / duplicate-group evidence
  └─ MatchConfidenceEngine
                  │
         ┌────────┴────────┐
         ▼                 ▼
confident             all other states
overlay + alignment   explanation + refusal
         │                 │
         └────────┬────────┘
                  ▼
provenance review + optional protected local save / deliberate share
```

City browse uses the archive path without injecting a meaningless placeholder into visual ranking. Automated matching tests inject a local thumbnail loader.

## Completed local slice

- Typed evidence, confidence, disposition, calibration, and candidate models separate policy from UI.
- Candidate-set normalization was removed; thresholds operate on absolute available signals.
- Heading contradictions and unavailable thumbnails remain inspectable instead of being dropped.
- Explicit confident, uncertain, insufficient-evidence, conflicting-signal, unavailable-location, and no-match states exist.
- The overlay is refusal-gated.
- Supporting, contradictory, and missing evidence plus archive provenance are presented.
- Field Walk supports candidate choice, comparison, manual alignment, provenance, protected local saving, and deliberate sharing.
- Deterministic Debug launch states use generated project-owned images.
- A frozen 13-case corpus measures calibration and negative refusal behavior.
- City cards reflect the live bundled index and disable cities with zero records.
- Two independent source-level design critiques were run and their highest-value findings were integrated.

## Remaining proof gates

### Gate A — Full Xcode integration

- Build and link the generated project.
- Run the entire XCTest suite, including new confidence, offline matching, local store, and export tests.
- Fix any compiler/concurrency/API issues found by the actual iOS SDK.

### Gate B — Simulator UX and accessibility

- Exercise every deterministic launch state on the smallest and largest supported simulators.
- Capture current screenshots and accessibility hierarchy/readback.
- Verify VoiceOver adjustable comparison, refusal announcements, save feedback, Dynamic Type reflow, contrast, scrolling, and hit targets.
- Run a visual critique on the actual rendered increment and implement material findings.

### Gate C — Runtime performance

- Measure spatial query, archive-image load, Vision ranking, total match latency, overlay drag frame pacing, export latency, memory, and energy.
- Move or bound any main-thread work revealed by profiling.
- Record target, OS, build configuration, samples, and raw evidence.

### Gate D — Bounded field evidence

- On an explicitly available device and test scene, verify permission recovery, location/heading dropout, network/cache behavior, refusal comprehension, alignment, and local save.
- Keep all efficacy claims bounded to labeled observations. Do not use arbitrary Photos or location history.

### Gate E — Data quality

- The current no-rebuild compatibility layer exposes missing source-record URL, ingestion/version lineage, coordinate provenance, and per-field quality without synthesis. Populate those fields only through a versioned nullable schema or sidecar table where future source-emitted data genuinely supports them.
- Decide whether to bundle licensed display images for real offline use; do not silently claim metadata-only bundling is a complete offline overlay.
- Re-audit city density before enabling cities or broad coverage copy.
- Evaluate full-resolution display assets separately from thumbnails, with network/privacy and memory constraints.

## Explicit non-goals without new authority

- downloading or changing archive datasets;
- uploading photos or location history;
- analytics or telemetry;
- publication, App Store submission, deployment, push, or media publication;
- AR, real-time viewfinder overlays, cloud sync, accounts, or user submissions;
- claims of general real-world matching efficacy.

## Definition of done

The upgrade is complete only when the current-state implementation, deterministic calibration/refusal suite, full Xcode tests, real UI and accessibility readback, runtime performance/energy evidence, bounded device field evidence, current docs, and limitation ledger all pass at the same reviewed binding. A green fixture verifier alone is not completion.
