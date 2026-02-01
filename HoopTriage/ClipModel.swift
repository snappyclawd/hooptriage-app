import Foundation
import AVFoundation

/// Represents a single video clip
struct Clip: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let filename: String
    let duration: Double
    
    var rating: Int = 0  // 0 = unrated, 1-5 = user rating
    var category: String? = nil
    
    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.filename = url.lastPathComponent
        
        // Get duration via AVAsset (fast — reads header only)
        let asset = AVURLAsset(url: url)
        self.duration = CMTimeGetSeconds(asset.duration)
    }
    
    var durationFormatted: String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return "\(mins):\(String(format: "%02d", secs))"
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
