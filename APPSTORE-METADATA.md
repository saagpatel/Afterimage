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
- **6.7" Display** — 1290 × 2796 px (iPhone 16 Pro Max / iPhone 15 Pro Max)
- **6.1" Display** — 1179 × 2556 px (iPhone 16 / iPhone 15)

### Screenshot Plan (4 screenshots per size)

| # | Screen | Simulator State | Headline Overlay |
|---|--------|-----------------|------------------|
| 1 | SliderView | Vertical slider at 50% — left half shows present-day NYC street, right half reveals an 1890s photograph of the same block | "Drag to reveal the past." |
| 2 | CameraView | Live camera viewfinder with semi-transparent historical photo overlay at ~30% opacity, compass heading indicator visible | "Stand where history happened." |
| 3 | MatchResultView | Best-match card: historical photo thumbnail, date (e.g. "ca. 1905"), distance badge "12m away", similarity score | "The same corner. 120 years apart." |
| 4 | GalleryView | Grid of historical photo thumbnails with city filter active (NYC), map pin count badge visible | "Thousands of moments. Six cities." |

### How to Take Screenshots
1. Open Xcode → Simulator → select iPhone 16 Pro Max
2. Build and run the Afterimage target
3. Use pre-seeded NYC test data for the slider and gallery views
4. **Xcode menu: Product → Simulator → Take Screenshot** (saves to Desktop)
   OR: `xcrun simctl io booted screenshot ~/Desktop/screenshot.png`
5. Repeat for iPhone 16 (6.1") by switching simulator
6. Add marketing text overlays in Sketch, Figma, or Canva before uploading

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
- [ ] All 8 screenshots uploaded (4 per required size)
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
