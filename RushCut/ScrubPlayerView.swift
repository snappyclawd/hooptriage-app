import SwiftUI
import AVFoundation
import AVKit

// MARK: - ScrubPlayerNSView

/// Lightweight NSView hosting an AVPlayerLayer for GPU-rendered video frames,
/// with a poster CALayer on top for flicker-free hover transitions.
///
/// The poster layer covers the player layer and stays visible until
/// `AVPlayerLayer.isReadyForDisplay` becomes true (KVO). This guarantees
/// the poster only hides once a real decoded frame is composited — not just
/// when the seek completes. Both layers live in Core Animation, so the
/// handoff is a single-frame, synchronous operation with no SwiftUI diffing.
final class ScrubPlayerNSView: NSView {
    
    let playerLayer = AVPlayerLayer()
    let posterLayer = CALayer()
    
    private var readyObservation: NSKeyValueObservation?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        // Player behind poster
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
        
        // Poster on top — covers the black player layer until a frame is ready
        posterLayer.contentsGravity = .resizeAspectFill
        posterLayer.masksToBounds = true
        layer?.addSublayer(posterLayer)
        
        // KVO: hide poster the instant AVPlayerLayer has a composited frame
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, change in
            guard let self, change.newValue == true else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.posterLayer.isHidden = true
            CATransaction.commit()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        posterLayer.frame = bounds
        CATransaction.commit()
    }
    
    func setPlayer(_ player: AVPlayer?) {
        // When clearing the player (hover-leave), re-show poster immediately
        if player == nil && playerLayer.player != nil {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            posterLayer.isHidden = false
            CATransaction.commit()
        }
        playerLayer.player = player
    }
    
    func setPosterImage(_ image: NSImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        posterLayer.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        CATransaction.commit()
    }
}

// MARK: - ScrubPlayerView (SwiftUI wrapper)

struct ScrubPlayerView: NSViewRepresentable {
    let player: AVPlayer?
    let posterImage: NSImage?
    
    func makeNSView(context: Context) -> ScrubPlayerNSView {
        let view = ScrubPlayerNSView(frame: .zero)
        view.setPlayer(player)
        view.setPosterImage(posterImage)
        return view
    }
    
    func updateNSView(_ nsView: ScrubPlayerNSView, context: Context) {
        nsView.setPlayer(player)
        nsView.setPosterImage(posterImage)
    }
}

// MARK: - Scrub Player Pool

/// Manages a pool of reusable AVPlayers with coalesced seeking.
///
/// Seek coalescing: only issue a new seek after the previous completes.
/// This prevents the decoder from being interrupted mid-frame, which
/// causes the choppy "smooth pocket then jump" pattern.
@MainActor
final class ScrubPlayerPool: ObservableObject {
    
    private var pool: [URL: AVPlayer] = [:]
    private var accessOrder: [URL] = []
    private let maxPoolSize = 12
    
    // Seek coalescing state
    private var isSeeking: [URL: Bool] = [:]
    private var pendingSeekTime: [URL: Double] = [:]
    private var playerURLs: [ObjectIdentifier: URL] = [:]
    
    /// Get or create a player for the given URL.
    func player(for url: URL) -> AVPlayer {
        if let existing = pool[url] {
            touchEntry(url)
            return existing
        }
        
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1.0
        
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        player.rate = 0
        
        pool[url] = player
        accessOrder.append(url)
        isSeeking[url] = false
        playerURLs[ObjectIdentifier(player)] = url
        
        while pool.count > maxPoolSize {
            let oldest = accessOrder.removeFirst()
            let evicted = pool[oldest]
            evicted?.pause()
            evicted?.replaceCurrentItem(with: nil)
            if let evicted = evicted {
                playerURLs.removeValue(forKey: ObjectIdentifier(evicted))
            }
            pool.removeValue(forKey: oldest)
            isSeeking.removeValue(forKey: oldest)
            pendingSeekTime.removeValue(forKey: oldest)
        }
        
        return player
    }
    
    /// Coalesced seek: if a seek is in flight, store the latest time
    /// and re-seek when the current one completes.
    /// The onFirstFrame callback fires once when the first seek completes —
    /// used to hide the poster and reveal the live player.
    func seek(_ player: AVPlayer, to time: Double, onFirstFrame: (() -> Void)? = nil) {
        guard let url = playerURLs[ObjectIdentifier(player)] else { return }
        
        if isSeeking[url] == true {
            pendingSeekTime[url] = time
            return
        }
        
        isSeeking[url] = true
        pendingSeekTime.removeValue(forKey: url)
        
        let cmTime = CMTime(seconds: max(time, 0.01), preferredTimescale: 600)
        // Zero tolerance — frame-perfect seeking. The coalesced seek pattern
        // ensures the decoder always finishes before starting the next frame.
        let tolerance = CMTime.zero
        
        player.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.isSeeking[url] = false
                
                onFirstFrame?()
                
                if let pending = self.pendingSeekTime[url] {
                    self.pendingSeekTime.removeValue(forKey: url)
                    self.seek(player, to: pending)
                }
            }
        }
    }
    
    func releaseAll() {
        for (_, player) in pool {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        pool.removeAll()
        accessOrder.removeAll()
        isSeeking.removeAll()
        pendingSeekTime.removeAll()
        playerURLs.removeAll()
    }
    
    private func touchEntry(_ url: URL) {
        if let idx = accessOrder.firstIndex(of: url) {
            accessOrder.remove(at: idx)
        }
        accessOrder.append(url)
    }
}
