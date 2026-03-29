# Afterimage

[![Swift](https://img.shields.io/badge/Swift-f05138?style=flat-square&logo=swift)](#) [![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](#)

> Point your camera at a street corner and see what it looked like in 1920.

Afterimage matches your photo to a geolocated historical photograph from the same location and reveals it beneath your shot using a draggable slider. All matching runs on-device against a bundled SQLite index — no backend, no accounts, no data leaves your phone.

## Features

- **Live camera matching** — take a photo and get a historical match in under 5 seconds
- **Four-stage pipeline** — spatial bounding-box query → heading filter (±45°) → thumbnail fetch → Vision feature-print re-ranking
- **Three comparison modes** — draggable slider (hero), side-by-side, and animated crossfade
- **Composite scoring** — 70% GPS/heading + 30% Vision similarity; labeled Strong Match, Good Match, or Nearby
- **Multi-match browsing** — up to 5 candidates in a horizontal thumbnail strip
- **Camera roll matching** — any photo with GPS EXIF metadata works
- **Share sheet** — exports a 1200×800 composite JPEG of then-and-now

## Quick Start

### Prerequisites
- Xcode 16+, iOS 17.0+
- Physical iPhone (camera and GPS required for end-to-end matching)

### Installation
```bash
git clone https://github.com/saagpatel/Afterimage.git
cd Afterimage
open Afterimage.xcodeproj
```

### Usage
Build and run on a physical iPhone. Tap the camera button, photograph a landmark, and the app returns its best historical match with the comparison controls.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Language | Swift 5.10, async/await |
| UI | SwiftUI (iOS 17+), AVFoundation camera wrapper |
| Database | GRDB.swift 7.x (typed SQLite wrappers) |
| Image loading | Kingfisher 8.x (async + disk cache) |
| ML similarity | Vision framework (VNGenerateImageFeaturePrintRequest) |
| Location | CoreLocation (CLLocationManager + CLHeading) |

## License

MIT
