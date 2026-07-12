# Afterimage — App Store metadata draft

This file is a pre-submission draft grounded in the current binary and bundled database. It is not evidence that an App Store Connect record exists or that the app passed archive validation.

## Identity

| Field | Draft value |
|---|---|
| Name | Afterimage |
| Subtitle | Compare Today With History |
| Bundle ID | `com.afterimage.app` |
| SKU | `AFTERIMAGE-001` |
| Primary category | Photo & Video |
| Secondary category | Education |
| Price | Free |

Age rating, territories, and pricing must be confirmed in App Store Connect rather than inferred here.

## Keywords

```text
historical photos,then and now,old photos,photo overlay,city history,archive,heritage
```

Confirm the final comma-separated value against App Store Connect's current character limit.

## Description

Stand where history happened—and compare the place in front of you with photographs from the past.

Afterimage uses your location, optional camera heading, and on-device image analysis to rank historical photographs taken nearby. Capture a photo or choose one from your library, then explore up to five results with Slider, Side by Side, and Fade comparison modes. You can also browse the bundled historical index by city and share a generated comparison image.

CURRENT COVERAGE

• New York City
• San Francisco
• Chicago
• More than 26,000 indexed historical-photo records from OldNYC and Wikimedia Commons

PRIVACY AND NETWORK USE

Afterimage has no account system, advertising SDK, analytics SDK, or Afterimage backend. Your selected photo and precise location are processed on device and are not uploaded by the app. The metadata index is bundled with the app, while historical images are downloaded over HTTPS from their source archives. A network connection is therefore required to display uncached historical images.

Camera, Photos, and location access are requested only for the features that need them.

## Promotional text

```text
Photograph a place and compare it with historical images taken nearby.
```

## URLs

- Support URL candidate: `https://github.com/saagpatel/Afterimage`
- Privacy Policy URL: **required before submission; not yet provided**
- Marketing URL: optional and not yet selected

The support repository must remain public and suitable for App Review before using it as the production support URL.

## Screenshot plan

Use the current App Store Connect screenshot requirements at submission time; do not rely on stale device-size assumptions in this repository.

Suggested current-product screenshots:

1. Comparison screen in Slider mode with a genuine matched pair.
2. Side by Side or Fade comparison mode.
3. Multiple-match selector with date and attribution.
4. Historical city gallery for one of the three shipped cities.
5. Camera permission or camera-ready surface only if captured on a physical device with real behavior.

Do not depict a live historical viewfinder overlay, six-city coverage, offline image availability, a similarity percentage, or navigation-to-photo features; those are not current product behavior.

## App Review notes draft

```text
Afterimage can match a captured or selected photo with historical photographs taken nearby.

Live capture flow:
1. Grant Camera and Location When In Use permissions.
2. Capture a photo.
3. The app obtains a location and, when available, a heading.
4. It searches the bundled metadata index and downloads candidate historical thumbnails from their source archives.
5. Select among the returned matches and use Slider, Side by Side, or Fade comparison modes.

Alternative flow:
1. Choose a photo from Photos.
2. If the selected asset does not expose a location, choose one on the map.
3. Continue through the same matching and comparison flow.

The Browse Cities button opens a read-only historical gallery for New York City, San Francisco, or Chicago. No account or login is required. Network access is required for historical images that are not already cached.
```

Before submission, replace this draft with physical-device steps that have been repeated successfully on the exact submitted build.

## Verified-in-repository facts

- Bundle ID: `com.afterimage.app`.
- Version/build currently resolve to `1.0` / `1`.
- Camera, Photos, and Location When In Use usage descriptions exist in `Afterimage/Info.plist`.
- `ITSAppUsesNonExemptEncryption` is `false`.
- `Afterimage/Resources/PrivacyInfo.xcprivacy` declares no tracking or collected-data types.
- The bundled SQLite file opens read-only and passes `PRAGMA integrity_check`.

These facts do not replace App Store Connect privacy answers, export-compliance review, or archive validation.

## Gates before App Store Connect upload

- [ ] Deep repository security scan completed and reportable findings resolved or explicitly dispositioned.
- [ ] Existing 25% Manhattan density gate passed or changed only through a documented product/data decision.
- [ ] Physical-device camera, location, heading, Photos, comparison, and share flows passed.
- [ ] Release device build and signed archive succeeded with the intended team/profile.
- [ ] App icon and asset catalog validated without warnings.
- [ ] Privacy manifest and App Privacy answers reviewed against actual network behavior.
- [ ] Public privacy-policy URL and support URL live and verified.
- [ ] Current App Store screenshot requirements checked and authentic screenshots produced.
- [ ] App Review notes replayed against the submitted build.

## Operator-only steps

Creating or changing the App Store Connect listing, uploading a build, setting territories/pricing, accepting agreements, completing legal questionnaires, inviting testers, and submitting for review require explicit operator approval.
