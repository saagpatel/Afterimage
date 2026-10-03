# App Store Metadata Draft — Not Ready for Submission

Updated: 2026-08-30

This file is a truthful drafting surface only. Do not submit or publish it until the runtime, accessibility, performance, privacy-disclosure, screenshot, and bounded field-proof gates in `docs/RUNNABLE-PROOF.md` pass at the release binding.

## Identity

| Field | Draft value |
|---|---|
| Name | Afterimage |
| Subtitle | History, With the Uncertainty Visible |
| Bundle ID | `com.afterimage.app` |
| Primary category | Photo & Video |
| Secondary category | Education |
| Price | Free |

## Draft description

Afterimage helps you inspect how a current street view may relate to nearby historical archive photographs.

Start with a photo and location. Afterimage evaluates the signals available on your device, shows nearby archive candidates, and explains what supports or contradicts each possible match. When the evidence is too weak, incomplete, or conflicting, Afterimage withholds the overlay rather than presenting guesswork as a precise identification.

For a supported candidate, compare past and present with a draggable divider, adjust the historical image alignment, review archive provenance, and save a before/after pair inside the app. You can separately choose to export a copy through the iOS share sheet.

Afterimage has no accounts, advertising, analytics, or Afterimage-operated backend. Your photo, precise location, and heading are processed on device. The archive metadata index is bundled with the app; uncached historical images are requested directly from their archive hosts.

Current archive records are concentrated in New York City, with smaller collections in Chicago and San Francisco. Coverage is uneven and a candidate is not a verified identification.

## Claims that must not appear before additional proof

- “exact spot,” “same viewpoint,” “verified match,” or any guaranteed accuracy wording;
- matching latency or frame-rate promises;
- “six covered cities”;
- “fully offline” or “no network required”;
- “no data leaves your phone” without explaining archive-host requests and deliberate sharing;
- live/real-time viewfinder matching;
- general field efficacy inferred from synthetic fixtures;
- a shippable status inferred from project generation, syntax parsing, or Debug screenshots.

## Screenshot proof plan

Use current rendered UI only. Synthetic fixture captures may document verification but must not imply a real historical match or be published as efficacy evidence.

Required internal proof states:

1. supported overlay with evidence summary and drag instruction;
2. uncertain candidate with overlay withheld;
3. conflicting signals with primary contradiction;
4. insufficient evidence;
5. unavailable location recovery;
6. no match;
7. city selector with zero-record cities disabled;
8. provenance, alignment, and local-save accessibility at large Dynamic Type.

Before any external screenshot use, capture on the release candidate, remove or label synthetic content, verify App Store size requirements current at submission time, and obtain explicit publication authority.

## App review notes draft

The core uncertainty states can be exercised in an internal Debug build with the fixture launch arguments documented in `docs/RUNNABLE-PROOF.md`. A submission build must not rely on undocumented reviewer-only behavior.

Camera and location permissions are requested only when their user-initiated flow needs them. If location is unavailable, the app preserves the photo and offers manual location choice. The app may retrieve historical thumbnails from the archive URL stored in its bundled metadata index.

## Pre-submission gate

- [ ] Release build and full tests pass on the submitted binding.
- [ ] Real Simulator/device visual and accessibility readback passes.
- [ ] Camera, location, heading, archive-network failure, and local-save paths pass on device.
- [ ] Performance, memory, and energy evidence is current.
- [ ] Privacy manifest, policy, and App Store disclosures agree with runtime behavior.
- [ ] City counts and coverage copy are re-read from the release database.
- [ ] No synthetic fixture is presented as a real match.
- [ ] Support and privacy URLs are verified current.
- [ ] Screenshots and all media have explicit publication authority.
- [ ] Limitation ledger is reviewed and release-blocking unknowns are resolved.
