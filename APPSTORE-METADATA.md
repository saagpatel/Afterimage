# Afterimage — App Store Connect Metadata

## Identity

| Field | Value |
|-------|-------|
| **Name** | Afterimage |
| **Subtitle** | History Through Your Camera |
| **Bundle ID** | com.afterimage.app |
| **SKU** | AFTERIMAGE-001 |
| **Primary Category** | Photo & Video |
| **Secondary Category** | Education |
| **Age Rating** | 4+ |
| **Price** | Free |
| **Availability** | All territories |

---

## Keywords

```
historical photos,then and now,old photos,photo overlay,city history,NYC history,time lapse,street view,archive,heritage
```

*(100 character limit)*

---

## Description

Stand where history happened — and see it.

Afterimage matches your camera view to a geolocated historical photograph from the same location, then lets you drag a vertical slider to reveal the past beneath the present. A 19th-century streetscape dissolves into today's skyline. A demolished building reappears in the exact spot where you're standing.

No accounts. No subscriptions. Everything runs on-device.

HOW IT WORKS

Afterimage uses your location and camera heading to find historical photos taken within meters of where you're standing, facing the same direction. A composite similarity score combines GPS distance, compass bearing, and on-device image analysis to surface the best match. Drag the slider to blend past and present.

WHAT'S INCLUDED

• Thousands of geolocated historical photographs from NYC, San Francisco, Chicago, Washington DC, New Orleans, and Boston
• On-device matching — no photos sent to any server, ever
• Draggable vertical reveal slider for seamless past/present comparison
• Camera mode: match your live viewfinder to a historical photo in real time
• Gallery mode: pick a historical photo and navigate to its exact location
• Offline-first: the entire photo index is bundled with the app

YOUR PRIVACY

Afterimage never transmits your photos, your location, or any usage data. Camera and location access are used exclusively on-device for matching. No accounts, no analytics, no telemetry.

---

## Promotional Text

*(Optional — appears above description, can be updated without a new app version)*

```
Point your camera at a city street and see the same block from 100 years ago.
```

---

## Support URL

https://github.com/d/Afterimage

---

## Privacy Policy URL

*(Required — can be a simple page stating no data is collected)*

---

## Screenshots

### Required Sizes
- **6.9" Display** — 1320 × 2868 px (iPhone 17 Pro Max). App Store Connect scales this down for smaller-device slots if only one size is uploaded.

### Screenshot Plan (screens that exist in the shipped app)

| # | Screen | Simulator State | Headline Overlay |
|---|--------|-----------------|------------------|
| 1 | ComparisonView | Mounted plate at 50% reveal — TODAY / era chips, divider handle, museum label with confidence line | "Drag to reveal the past." |
| 2 | CitySelectorView | "The Collection" catalog: six city cards | "Six cities. Thousands of photographs." |
| 3 | CameraView (enable state) | "Tap to Enable Camera" with Choose a Photo / Browse Covered Cities actions | "Stand where history happened." |

### How to Capture

```
bash scripts/capture-screenshots.sh
```

Builds, installs on the iPhone 17 Pro Max simulator, and captures all
three scenes to `screenshots/iphone-69/` at native 1320×2868 using the
DEBUG demo launch arguments (`--afterimage-demo-comparison`,
`--afterimage-demo-cities`).

**Before submission:** the demo comparison fixture uses synthetic proof
images. The committed captures verify the design and pipeline; the
shipped screenshot 1 must be recaptured with a real match (real photo at
a covered location, on device), and marketing text overlays added in
Figma/Canva. Screenshots 2–3 are shippable as captured.

---

## App Review Notes

```
Afterimage requires camera and location permissions to match live camera views to historical photos.

To test the core flow:
1. Grant camera and location permissions when prompted
2. Tap the camera icon to enter camera mode
3. The app will find nearby historical photos matching your direction
4. A match result card appears — tap it to enter the slider view
5. Drag the vertical slider to reveal the historical photo beneath the present-day view

For review without a physical location match, use Gallery mode:
1. Tap "Gallery" and browse the bundled historical photos
2. Tap any photo to see its metadata and navigate to its location on the map
3. Tap "Go Here" to enter camera mode aimed at that location

No network connection is required. All photo matching is on-device.
No account or login is required at any point.
```

---

## Checklist Before Submission

- [ ] Bundle ID `com.afterimage.app` registered in Apple Developer portal
- [ ] App icon 1024×1024 appears correctly in Xcode asset catalog (no warnings)
- [ ] Archive succeeds: `Product → Archive` with no errors
- [ ] Validate App passes with 0 errors (check privacy manifest, entitlements)
- [ ] Screenshot 1 recaptured with a real match on device (synthetic fixture is not shippable)
- [ ] All screenshots uploaded at 6.9" (1320 × 2868)
- [ ] Description, keywords, subtitle filled in App Store Connect
- [ ] Price set to Free in Pricing and Availability
- [ ] Age rating questionnaire complete (4+)
- [ ] Support URL and Privacy Policy URL provided
- [ ] Camera usage description present in Info.plist (`NSCameraUsageDescription`)
- [ ] Location usage description present in Info.plist (`NSLocationWhenInUseUsageDescription`)
- [ ] PrivacyInfo.xcprivacy declares camera, location, and file access reasons
- [ ] `photos.db` bundled asset is read-only and not writable at runtime
- [ ] TestFlight internal test complete (camera match flow, slider interaction, gallery browsing)
- [ ] Submit for Review
