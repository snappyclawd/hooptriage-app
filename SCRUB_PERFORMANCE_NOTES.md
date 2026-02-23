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

### Black flash on hover-enter
The poster image hides before `AVPlayerLayer` renders its first decoded frame. Current mitigation: keep poster visible until `onFirstFrame` callback fires from the first coalesced seek. Still flickers because SwiftUI's view diffing may introduce a frame gap.

**Likely fix:** Move the poster image into `ScrubPlayerNSView` as a `CALayer` positioned behind the `AVPlayerLayer`. On hover-enter, the poster CALayer is already showing. When AVPlayerLayer renders its first frame, hide the poster CALayer. This keeps the entire transition in Core Animation — no SwiftUI diffing involved.

### Virtualized grid
`LazyVGrid` handles basic lazy loading but keeps many off-screen views alive. With 500+ clips, this could cause memory pressure and scroll jank. A true virtualized grid (like TanStack Virtual for web) would only maintain views for visible clips + a small buffer. Not yet implemented — current scroll performance is acceptable but could improve.

### Scroll flicker
When scrolling fast, `LazyVGrid` destroys and recreates `ClipThumbnailView` instances. The `@State posterImage` resets to nil, causing a brief black frame before the `ThumbnailGenerator` cache returns the poster. The cache hit is fast (actor hop) but not synchronous. Moving poster display into an `NSView` layer that reads from a shared synchronous cache would eliminate this.
