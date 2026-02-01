import Foundation
import AVFoundation

/// Represents a single video clip
struct Clip: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let filename: String
    let duration: Double
    let width: Int
    let height: Int
    let fileSize: Int64
    
    var rating: Int = 0  // 0 = unrated, 1-5 = user rating
    var category: String? = nil
    
    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.filename = url.lastPathComponent
        
        // Get duration and video dimensions via AVAsset (fast — reads header only)
        let asset = AVURLAsset(url: url)
        self.duration = CMTimeGetSeconds(asset.duration)
        
        // Get video dimensions from first video track
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            self.width = Int(abs(size.width))
            self.height = Int(abs(size.height))
        } else {
            self.width = 0
            self.height = 0
        }
        
        // Get file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            self.fileSize = size
        } else {
            self.fileSize = 0
        }
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
