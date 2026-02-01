# 🏀 HoopTriage

Native macOS app for triaging basketball footage. GPU-accelerated scrubbing, instant review.

## The Problem

You filmed a basketball tournament. You have 1,200+ short clips. Sorting them takes an entire day.

## The Solution

Drag a folder into HoopTriage. Instantly see all your clips in a grid. Hover to scrub through any clip — GPU-accelerated, no pre-processing, no waiting. Rate clips, filter, sort, and get back to editing.

## Features

- **Drag & drop** — drop a folder and clips appear instantly
- **Hover scrub** — mouse across any clip to scrub through it. GPU-accelerated via AVFoundation. No lag.
- **Star ratings** — click stars or use keyboard (1-5) to rate clips
- **Grid size** — slider to adjust from 1 to 8 columns
- **Sort & filter** — by name, duration, or rating
- **Double-click to play** — opens an expanded player with full controls

## Requirements

- macOS 14.0+
- Xcode 15+

## Build & Run

```bash
git clone https://github.com/snappyclawd/hooptriage-app.git
cd hooptriage-app
open HoopTriage.xcodeproj
```

In Xcode, hit **⌘R** to build and run.

## How It Works

Uses Apple's `AVAssetImageGenerator` for thumbnail generation — this is the same hardware-accelerated video decoding pipeline that professional video apps use. No ffmpeg, no pre-processing, no proxies. Just raw GPU power.

## 100% Local

No internet required. No uploads. Your footage never leaves your machine.

## License

MIT
