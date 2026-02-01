import Foundation
import SwiftUI

/// Sort options for the clip grid
enum SortOrder: String, CaseIterable {
    case name = "Name"
    case duration = "Duration"
    case rating = "Rating"
}

/// Default basketball tags
let defaultTags = [
    "Action",
    "Three",
    "Dunk",
    "Huddle",
    "Warmup",
    "Establishment",
    "Interview",
    "Celebration",
    "Defense",
    "Fast Break",
]

/// Main data store for all clips
@MainActor
class ClipStore: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var folderURL: URL? = nil
    @Published var sortOrder: SortOrder = .name
    @Published var filterRating: Int = 0 // 0 = show all
    @Published var filterTag: String? = nil
    @Published var gridColumns: Int = 4
    @Published var availableTags: [String] = defaultTags
    
    let thumbnailGenerator = ThumbnailGenerator()
    
    var sortedAndFilteredClips: [Clip] {
        var result = clips
        
        // Filter by rating
        if filterRating > 0 {
            result = result.filter { $0.rating == filterRating }
        }
        
        // Filter by tag
        if let tag = filterTag {
            result = result.filter { $0.category == tag }
        }
        
        // Sort
        switch sortOrder {
        case .name:
            result.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        case .duration:
            result.sort { $0.duration > $1.duration }
        case .rating:
            result.sort { $0.rating > $1.rating }
        }
        
        return result
    }
    
    /// Tags currently in use by clips
    var usedTags: [String] {
        let tags = Set(clips.compactMap { $0.category })
        return availableTags.filter { tags.contains($0) }
    }
    
    /// Load clips from a directory
    func loadFolder(_ url: URL) {
        folderURL = url
        isLoading = true
        loadingProgress = 0
        clips = []
        
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                await MainActor.run { self.isLoading = false }
                return
            }
            
            var videoURLs: [URL] = []
            while let fileURL = enumerator.nextObject() as? URL {
                let ext = fileURL.pathExtension.lowercased()
                if supportedExtensions.contains(ext) {
                    videoURLs.append(fileURL)
                }
            }
            
            videoURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            
            let total = videoURLs.count
            
            for (index, fileURL) in videoURLs.enumerated() {
                let clip = Clip(url: fileURL)
                
                await MainActor.run {
                    self.clips.append(clip)
                    self.loadingProgress = Double(index + 1) / Double(total)
                }
            }
            
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    /// Update a clip's rating
    func setRating(_ rating: Int, for clipID: UUID) {
        if let index = clips.firstIndex(where: { $0.id == clipID }) {
            clips[index].rating = clips[index].rating == rating ? 0 : rating
        }
    }
    
    /// Update a clip's category
    func setCategory(_ category: String?, for clipID: UUID) {
        if let index = clips.firstIndex(where: { $0.id == clipID }) {
            clips[index].category = category
        }
    }
    
    /// Add a new tag to available tags
    func addTag(_ tag: String) {
        if !availableTags.contains(tag) {
            availableTags.append(tag)
        }
    }
    
    /// Open folder picker
    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder with video clips"
        panel.prompt = "Open"
        
        if panel.runModal() == .OK, let url = panel.url {
            loadFolder(url)
        }
    }
    
    // MARK: - Stats
    
    var totalClips: Int { clips.count }
    var ratedClips: Int { clips.filter { $0.rating > 0 }.count }
    var taggedClips: Int { clips.filter { $0.category != nil }.count }
    var totalDuration: Double { clips.reduce(0) { $0 + $1.duration } }
    
    var totalDurationFormatted: String {
        let mins = Int(totalDuration) / 60
        let secs = Int(totalDuration) % 60
        if mins > 60 {
            let hrs = mins / 60
            let remainingMins = mins % 60
            return "\(hrs)h \(remainingMins)m"
        }
        return "\(mins)m \(secs)s"
    }
}
