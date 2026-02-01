import Foundation
import AVFoundation
import AppKit

/// GPU-accelerated thumbnail generation using AVAssetImageGenerator
actor ThumbnailGenerator {
    
    // Cache generated images to avoid re-generating
    private var cache: [String: NSImage] = [:]
    
    /// Generate a thumbnail at a specific time for a clip.
    /// Uses AVAssetImageGenerator which leverages hardware video decoding.
    func thumbnail(for url: URL, at time: Double, size: CGSize = CGSize(width: 320, height: 180)) async -> NSImage? {
        let cacheKey = "\(url.path)_\(String(format: "%.2f", time))_\(Int(size.width))"
        
        if let cached = cache[cacheKey] {
            return cached
        }
        
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        
        // Allow approximate time for speed (don't seek to exact frame)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        
        let cmTime = CMTime(seconds: max(time, 0.01), preferredTimescale: 600)
        
        do {
            let (cgImage, _) = try await generator.image(at: cmTime)
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            cache[cacheKey] = image
            return image
        } catch {
            return nil
        }
    }
    
    /// Generate a poster (thumbnail at 25% of duration)
    func poster(for url: URL, duration: Double, size: CGSize = CGSize(width: 320, height: 180)) async -> NSImage? {
        return await thumbnail(for: url, at: duration * 0.25, size: size)
    }
    
    /// Clear cache for memory management
    func clearCache() {
        cache.removeAll()
    }
    
    /// Remove cached entries for a specific clip
    func clearCache(for url: URL) {
        cache = cache.filter { !$0.key.hasPrefix(url.path) }
    }
}
