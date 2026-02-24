import Foundation
import AVFoundation

/// Represents a single video clip
struct Clip: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var filename: String
    let duration: Double
    let width: Int
    let height: Int
    let fileSize: Int64
    
    var rating: Int = 0              // 0 = unrated, 1-5 = user rating
    var tags: [String] = []
    
    /// Create a clip by async-loading metadata from the file
    static func create(url: URL) async -> Clip {
        let asset = AVURLAsset(url: url)
        
        // Load duration
        var dur: Double = 0
        if let cmDuration = try? await asset.load(.duration) {
            dur = CMTimeGetSeconds(cmDuration)
        }
        
        // Load video dimensions from first video track
        var w = 0
        var h = 0
        if let tracks = try? await asset.loadTracks(withMediaType: .video),
           let track = tracks.first {
            if let (naturalSize, transform) = try? await track.load(.naturalSize, .preferredTransform) {
                let size = naturalSize.applying(transform)
                w = Int(abs(size.width))
                h = Int(abs(size.height))
            }
        }
        
        // Get file size (sync — just reads filesystem metadata)
        var size: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let s = attrs[.size] as? Int64 {
            size = s
        }
        
        return Clip(
            id: UUID(),
            url: url,
            filename: url.lastPathComponent,
            duration: dur,
            width: w,
            height: h,
            fileSize: size
        )
    }
    
    var durationFormatted: String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
    
    var fileSizeFormatted: String? {
        guard fileSize > 0 else { return nil }
        let mb = Double(fileSize) / 1_048_576
        if mb > 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
    
    static func == (lhs: Clip, rhs: Clip) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Supported video extensions
let supportedExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "mts", "webm"]
