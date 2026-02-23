import Foundation
import AVFoundation
import AppKit

/// High-performance thumbnail generation with asset reuse, LRU cache,
/// and cancellation support.
actor ThumbnailGenerator {
    
    // MARK: - LRU Cache
    
    /// Max number of thumbnails to keep in memory.
    /// At 480x270 JPEG-quality, each is roughly 50-100KB.
    /// 2000 entries ≈ 100-200MB — reasonable for a triage session.
    private let maxCacheSize = 2000
    
    /// Cache: key → NSImage
    private var cache: [String: NSImage] = [:]
    
    /// Access order for LRU eviction (most recent at end)
    private var accessOrder: [String] = []
    
    // MARK: - Asset Pool
    
    /// Reuse AVURLAsset instances per URL to avoid repeated file handle + header parsing.
    private var assetPool: [URL: AVURLAsset] = [:]
    
    /// Track pool size and evict least-recently-used assets if it grows too large.
    private var assetAccessOrder: [URL] = []
    private let maxAssetPoolSize = 50
    
    // MARK: - Generator Pool
    
    /// Reuse AVAssetImageGenerator per URL. These hold internal decoder state
    /// and are significantly faster on subsequent calls than creating new ones.
    private var generatorPool: [URL: AVAssetImageGenerator] = [:]
    
    // MARK: - Pre-warming
    
    /// Pre-generate a strip of thumbnails for a clip at evenly spaced intervals.
    /// Call this on folder load for visible clips to eliminate first-hover latency.
    func prewarm(url: URL, duration: Double, count: Int = 20, size: CGSize = CGSize(width: 480, height: 270)) async {
        guard duration > 0 else { return }
        for i in 0..<count {
            let time = duration * Double(i) / Double(count - 1)
            // This populates the cache; result is discarded
            let _ = await thumbnail(for: url, at: time, size: size)
        }
    }
    
    // MARK: - Thumbnail Generation
    
    /// Generate a thumbnail at a specific time for a clip.
    /// Reuses assets and generators. Results are LRU-cached.
    func thumbnail(for url: URL, at time: Double, size: CGSize = CGSize(width: 480, height: 270)) async -> NSImage? {
        let cacheKey = "\(url.path)_\(String(format: "%.2f", time))_\(Int(size.width))"
        
        // Check cache
        if let cached = cache[cacheKey] {
            touchCacheEntry(cacheKey)
            return cached
        }
        
        // Get or create a reusable asset
        let asset = getOrCreateAsset(for: url)
        
        // Get or create a reusable generator
        let generator = getOrCreateGenerator(for: url, asset: asset, size: size)
        
        let cmTime = CMTime(seconds: max(time, 0.01), preferredTimescale: 600)
        
        do {
            let (cgImage, _) = try await generator.image(at: cmTime)
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            insertCache(key: cacheKey, image: image)
            return image
        } catch {
            return nil
        }
    }
    
    /// Generate a poster (thumbnail at 25% of duration)
    func poster(for url: URL, duration: Double, size: CGSize = CGSize(width: 480, height: 270)) async -> NSImage? {
        return await thumbnail(for: url, at: duration * 0.25, size: size)
    }
    
    /// Check if a poster is already cached (actor-isolated, but fast path).
    func cachedPoster(for url: URL, duration: Double, size: CGSize = CGSize(width: 480, height: 270)) -> NSImage? {
        let time = duration * 0.25
        let cacheKey = "\(url.path)_\(String(format: "%.2f", time))_\(Int(size.width))"
        if let cached = cache[cacheKey] {
            touchCacheEntry(cacheKey)
            return cached
        }
        return nil
    }
    
    // MARK: - Asset Pool Management
    
    private func getOrCreateAsset(for url: URL) -> AVURLAsset {
        if let existing = assetPool[url] {
            touchAssetEntry(url)
            return existing
        }
        
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        assetPool[url] = asset
        assetAccessOrder.append(url)
        
        // Evict oldest if pool is full
        while assetPool.count > maxAssetPoolSize {
            let oldest = assetAccessOrder.removeFirst()
            assetPool.removeValue(forKey: oldest)
            generatorPool.removeValue(forKey: oldest)
        }
        
        return asset
    }
    
    private func getOrCreateGenerator(for url: URL, asset: AVURLAsset, size: CGSize) -> AVAssetImageGenerator {
        if let existing = generatorPool[url] {
            // Update size in case it changed
            existing.maximumSize = size
            return existing
        }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        
        // Allow approximate time — snap to nearest keyframe for speed.
        // 0.5s tolerance means the decoder can use a nearby keyframe
        // instead of decoding from the previous keyframe to the exact time.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        
        generatorPool[url] = generator
        return generator
    }
    
    // MARK: - Cache Management
    
    private func touchCacheEntry(_ key: String) {
        if let idx = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: idx)
        }
        accessOrder.append(key)
    }
    
    private func touchAssetEntry(_ url: URL) {
        if let idx = assetAccessOrder.firstIndex(of: url) {
            assetAccessOrder.remove(at: idx)
        }
        assetAccessOrder.append(url)
    }
    
    private func insertCache(key: String, image: NSImage) {
        cache[key] = image
        accessOrder.append(key)
        
        // Evict oldest entries if over limit
        while cache.count > maxCacheSize {
            let oldest = accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
    
    /// Clear all caches
    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
        assetPool.removeAll()
        assetAccessOrder.removeAll()
        generatorPool.removeAll()
    }
    
    /// Remove cached entries for a specific clip
    func clearCache(for url: URL) {
        let keysToRemove = cache.keys.filter { $0.hasPrefix(url.path) }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            if let idx = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: idx)
            }
        }
        assetPool.removeValue(forKey: url)
        generatorPool.removeValue(forKey: url)
        if let idx = assetAccessOrder.firstIndex(of: url) {
            assetAccessOrder.remove(at: idx)
        }
    }
}
