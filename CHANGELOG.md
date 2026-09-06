# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Typed match evidence, confidence, disposition, calibration, and refusal policy.
- Explanations for supporting, contradictory, and missing evidence.
- An uncertainty-aware Field Walk with candidate inspection, gated overlay, alignment, provenance, protected local pair saving, and deliberate sharing.
- Deterministic Debug launch states and a frozen negative-heavy calibration corpus.
- A typed no-rebuild provenance compatibility layer, explicit lineage gaps, and a standalone provenance verifier.
- Explicit product, runnable-proof, privacy, and limitation documentation.

### Changed

- Replaced candidate-relative score normalization with absolute evidence thresholds.
- Preserved heading contradictions and unavailable archive images for inspection.
- Made heading evidence conservative to compass accuracy and archive metadata confidence.
- Separated compact archive details from expandable audit lineage and distinguished rights-link presence from verification.
- Made city browse skip meaningless placeholder-image Vision ranking and reflect bundled city counts.

### Verification boundary

- Toolchain-light fixture and data-pipeline checks pass locally.
- Full Xcode build/XCTest, Simulator accessibility, device field use, and app performance/energy evidence remain open; see `docs/LIMITATIONS.md`.
