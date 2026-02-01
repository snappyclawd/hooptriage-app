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

// MARK: - Undo System

/// A single undoable action
enum UndoAction: CustomStringConvertible {
    case setRating(clipID: UUID, oldRating: Int, newRating: Int)
    case toggleTag(clipID: UUID, tag: String, wasAdded: Bool)  // wasAdded: true = tag was added, false = tag was removed
    case removeClip(clip: Clip, index: Int)
    case addClips(clipIDs: [UUID])
    
    var description: String {
        switch self {
        case .setRating(_, let old, let new):
            return new == 0 ? "Clear Rating" : "Rate \(old)→\(new)★"
        case .toggleTag(_, let tag, let wasAdded):
            return wasAdded ? "Add '\(tag)'" : "Remove '\(tag)'"
        case .removeClip(let clip, _):
            return "Remove '\(clip.filename)'"
        case .addClips(let ids):
            return "Add \(ids.count) clip\(ids.count == 1 ? "" : "s")"
        }
    }
}

/// Main data store for all clips
@MainActor
class ClipStore: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var sortOrder: SortOrder = .name
    @Published var filterRating: Int = 0 // 0 = show all
    @Published var filterTag: String? = nil
    @Published var gridColumns: Int = 3
    @Published var groupMode: GroupMode = .none
    @Published var availableTags: [String] = defaultTags
    @Published var showTagPickerForClipID: UUID? = nil
    @Published var hoveredClipID: UUID? = nil
    
    // Undo/Redo stacks
    @Published var undoStack: [UndoAction] = []
    @Published var redoStack: [UndoAction] = []
    
    var undoDescription: String? {
        undoStack.last.map { "Undo \($0.description)" }
    }
    
    var redoDescription: String? {
        redoStack.last.map { "Redo \($0.description)" }
    }
    
    let thumbnailGenerator = ThumbnailGenerator()
    
    private var loadedURLs: Set<URL> = []
    
    var sortedAndFilteredClips: [Clip] {
        var result = clips
        
        if filterRating > 0 {
            result = result.filter { $0.rating == filterRating }
        }
        
        if let tag = filterTag {
            result = result.filter { $0.tags.contains(tag) }
        }
        
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
    
    /// All tags currently in use by at least one clip
    var usedTags: [String] {
        let allUsed = clips.reduce(into: Set<String>()) { $0.formUnion($1.tags) }
        return availableTags.filter { allUsed.contains($0) }
    }
    
    // MARK: - Add Folder (additive)
    
    func addFolder(_ url: URL) {
        isLoading = true
        loadingProgress = 0
        
        Task { [weak self] in
            guard let self = self else { return }
            
            let videoURLs: [URL] = await Task.detached {
                let fm = FileManager.default
                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { return [URL]() }
                
                var urls: [URL] = []
                while let fileURL = enumerator.nextObject() as? URL {
                    let ext = fileURL.pathExtension.lowercased()
                    if supportedExtensions.contains(ext) {
                        urls.append(fileURL)
                    }
                }
                urls.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                return urls
            }.value
            
            let newURLs = videoURLs.filter { !self.loadedURLs.contains($0) }
            
            let total = newURLs.count
            guard total > 0 else {
                self.isLoading = false
                return
            }
            
            var addedIDs: [UUID] = []
            
            for (index, fileURL) in newURLs.enumerated() {
                let clip = await Clip.create(url: fileURL)
                self.clips.append(clip)
                self.loadedURLs.insert(fileURL)
                self.loadingProgress = Double(index + 1) / Double(total)
                addedIDs.append(clip.id)
            }
            
            self.isLoading = false
            if !addedIDs.isEmpty {
                self.pushUndo(.addClips(clipIDs: addedIDs))
            }
        }
    }
    
    func addClip(url: URL) {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return }
        guard !loadedURLs.contains(url) else { return }
        
        loadedURLs.insert(url)
        Task {
            let clip = await Clip.create(url: url)
            clips.append(clip)
            pushUndo(.addClips(clipIDs: [clip.id]))
        }
    }
    
    // MARK: - Remove Clip
    
    func removeClip(id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = clips[index]
        clips.remove(at: index)
        loadedURLs.remove(clip.url)
        pushUndo(.removeClip(clip: clip, index: index))
    }
    
    // MARK: - Rating & Tags (with undo)
    
    func setRating(_ rating: Int, for clipID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        let oldRating = clips[index].rating
        let newRating = oldRating == rating ? 0 : rating
        clips[index].rating = newRating
        pushUndo(.setRating(clipID: clipID, oldRating: oldRating, newRating: newRating))
    }
    
    /// Toggle a tag on a clip (add if missing, remove if present)
    func toggleTag(_ tag: String, for clipID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        if clips[index].tags.contains(tag) {
            clips[index].tags.remove(tag)
            pushUndo(.toggleTag(clipID: clipID, tag: tag, wasAdded: false))
        } else {
            clips[index].tags.insert(tag)
            pushUndo(.toggleTag(clipID: clipID, tag: tag, wasAdded: true))
        }
    }
    
    /// Remove a specific tag from a clip
    func removeTag(_ tag: String, for clipID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        if clips[index].tags.contains(tag) {
            clips[index].tags.remove(tag)
            pushUndo(.toggleTag(clipID: clipID, tag: tag, wasAdded: false))
        }
    }
    
    func addTag(_ tag: String) {
        if !availableTags.contains(tag) {
            availableTags.append(tag)
        }
    }
    
    // MARK: - Undo / Redo
    
    private func pushUndo(_ action: UndoAction) {
        undoStack.append(action)
        redoStack.removeAll()
        if undoStack.count > 100 {
            undoStack.removeFirst(undoStack.count - 100)
        }
    }
    
    func undo() {
        guard let action = undoStack.popLast() else { return }
        
        switch action {
        case .setRating(let clipID, let oldRating, _):
            if let index = clips.firstIndex(where: { $0.id == clipID }) {
                clips[index].rating = oldRating
            }
            
        case .toggleTag(let clipID, let tag, let wasAdded):
            if let index = clips.firstIndex(where: { $0.id == clipID }) {
                if wasAdded {
                    // It was added, so undo = remove
                    clips[index].tags.remove(tag)
                } else {
                    // It was removed, so undo = add back
                    clips[index].tags.insert(tag)
                }
            }
            
        case .removeClip(let clip, let index):
            let insertAt = min(index, clips.count)
            clips.insert(clip, at: insertAt)
            loadedURLs.insert(clip.url)
            
        case .addClips(let clipIDs):
            let idSet = Set(clipIDs)
            let removed = clips.filter { idSet.contains($0.id) }
            clips.removeAll { idSet.contains($0.id) }
            for clip in removed {
                loadedURLs.remove(clip.url)
            }
        }
        
        redoStack.append(action)
    }
    
    func redo() {
        guard let action = redoStack.popLast() else { return }
        
        switch action {
        case .setRating(let clipID, _, let newRating):
            if let index = clips.firstIndex(where: { $0.id == clipID }) {
                clips[index].rating = newRating
            }
            
        case .toggleTag(let clipID, let tag, let wasAdded):
            if let index = clips.firstIndex(where: { $0.id == clipID }) {
                if wasAdded {
                    clips[index].tags.insert(tag)
                } else {
                    clips[index].tags.remove(tag)
                }
            }
            
        case .removeClip(let clip, _):
            clips.removeAll { $0.id == clip.id }
            loadedURLs.remove(clip.url)
            
        case .addClips:
            break
        }
        
        undoStack.append(action)
    }
    
    // MARK: - Folder Picker
    
    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = []
        panel.message = "Select folders or video files to add"
        panel.prompt = "Add"
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                
                if isDir.boolValue {
                    addFolder(url)
                } else {
                    addClip(url: url)
                }
            }
        }
    }
    
    // MARK: - Stats
    
    var totalClips: Int { clips.count }
    var ratedClips: Int { clips.filter { $0.rating > 0 }.count }
    var taggedClips: Int { clips.filter { !$0.tags.isEmpty }.count }
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
