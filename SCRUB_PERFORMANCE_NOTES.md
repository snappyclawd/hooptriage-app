# Scrub Performance Notes

## Current architecture

- **AVPlayer + AVPlayerLayer** renders scrub frames directly via GPU (same pipeline as QuickTime)
- **Coalesced seeking** in `ScrubPlayerPool` — only one seek in flight at a time; pending seeks are queued and the latest is applied when the current completes. Prevents decoder stutter from seek spam.
- **Zero tolerance seeking** (`CMTime.zero`) — frame-perfect. Works because coalescing protects the decoder from being interrupted mid-frame.
- **Player pool** (LRU, max 12) — reuses warm `AVPlayer` instances across clips. Player is only acquired from pool on hover-enter, not on view creation.
- **Static poster** generated once per clip via `ThumbnailGenerator` using `AVAssetImageGenerator` with asset/generator reuse and LRU cache (max 2000 entries).

## What worked

| Change | Impact |
|---|---|
| AVPlayer instead of AVAssetImageGenerator for scrubbing | Eliminated CGImage round-trip; frames go GPU -> screen |
| Coalesced seeks | Stopped decoder interruption; smooth frame delivery |
| Zero tolerance | Best accuracy + smoothness (counter-intuitive but works with coalescing) |
| Player pool with LRU eviction | Re-hovering recent clips reuses warm decoder |
| `.task(id: clip.id)` for poster loading | Prevents redundant generation on scroll |

## What didn't work

| Attempt | Why it failed |
|---|---|
| Browser/HTML POC (`<video>` elements) | One `<video>` per clip choked the browser. Single shared video still sluggish — browsers don't expose seek tolerance or decoder priority. JavaScript can't match native for this use case. |
| AVAssetImageGenerator for scrubbing | Creates new AVURLAsset + AVAssetImageGenerator per request. Even with debouncing/cancellation/pooling, the CGImage creation round-trip is too slow for real-time scrubbing. |
| Full NSView mouse tracking (moving all interaction to AppKit) | Broke everything — `ScrubPlayerView` was initialized eagerly in SwiftUI body for every visible clip, creating hundreds of AVPlayers on scroll. |
| Wide seek tolerance (0.3s) | Too jumpy — skips too much content with small mouse movements. Users need to see the actual frames they're scrubbing through. |
| Tight-ish tolerance (0.1s) | Better but still had "smooth pocket then jump" pattern at keyframe boundaries. |

## Still open

### Black flash on hover-enter — FIXED
The poster image used to hide before `AVPlayerLayer` rendered its first decoded frame. The original mitigation (keep SwiftUI poster visible until `onFirstFrame` callback) still flickered because SwiftUI's view diffing introduced a frame gap.

**Fix applied:** Moved the poster into `ScrubPlayerNSView` as a `CALayer` positioned behind the `AVPlayerLayer`. The `ScrubPlayerView` is now always present (not conditional on hover), with poster and player layers both in Core Animation. On hover-enter, the poster CALayer is already showing. When AVPlayerLayer renders its first frame (`scrubPlayerReady = true`), the poster layer hides via `CATransaction` — no SwiftUI diffing involved. The `Color.black` background and conditional `Image(nsImage:)` have been removed from `ClipThumbnailView`.

### Virtualized grid
`LazyVGrid` handles basic lazy loading but keeps many off-screen views alive. With 500+ clips, this could cause memory pressure and scroll jank. A true virtualized grid (like TanStack Virtual for web) would only maintain views for visible clips + a small buffer. Not yet implemented — current scroll performance is acceptable but could improve.

### Scroll flicker — FIXED
When scrolling fast, `LazyVGrid` destroys and recreates `ClipThumbnailView` instances. The `@State posterImage` resets to nil. The actor-isolated LRU cache requires an async hop, so there was always at least one black frame.

**Fix applied:** Added a `nonisolated` `NSCache<NSURL, NSImage>` (`posterCache`) to `ThumbnailGenerator`. It's populated whenever `poster()` generates an image. In `ClipThumbnailView`, the poster passed to `ScrubPlayerView` uses a sync fallback: `posterImage ?? thumbnailGenerator.cachedPosterSync(for:duration:size:)`. This reads from `NSCache` (thread-safe, no await, no actor hop) so the `ScrubPlayerNSView` poster layer has content from the very first frame — even when `@State posterImage` is nil after view recreation.
