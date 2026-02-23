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
    case toggleTag(clipID: UUID, tag: String, wasAdded: Bool)
    case removeClip(clip: Clip, index: Int)
    case addClips(clipIDs: [UUID])
    case audioTriage(suggestions: [(UUID, Int)])              // bulk suggested ratings
    case acceptSuggestion(clipID: UUID, suggestedRating: Int) // single accept
    case acceptAllSuggestions(accepted: [(UUID, Int)])         // bulk accept
    case dismissSuggestion(clipID: UUID, suggestedRating: Int)
    
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
        case .audioTriage(let suggestions):
            return "Audio Triage (\(suggestions.count) clips)"
        case .acceptSuggestion:
            return "Accept Suggestion"
        case .acceptAllSuggestions(let accepted):
            return "Accept All (\(accepted.count) clips)"
        case .dismissSuggestion:
            return "Dismiss Suggestion"
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
    let scrubPlayerPool = ScrubPlayerPool()
    let audioScrubEngine = AudioScrubEngine()
    
    private var loadedURLs: Set<URL> = []
    
    var sortedAndFilteredClips: [Clip] {
        var result = clips
        
        if filterRating > 0 {
            result = result.filter { $0.effectiveRating == filterRating }
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
            result.sort { $0.effectiveRating > $1.effectiveRating }
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
    
    // MARK: - Audio Triage (Suggestions)
    
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    
    /// Number of clips with unconfirmed suggestions
    var suggestedCount: Int {
        clips.filter { $0.hasSuggestion }.count
    }
    
    /// Run audio analysis on unrated clips and assign suggested ratings
    func runAudioTriage() {
        let unratedClips = clips.filter { $0.rating == 0 && $0.suggestedRating == 0 }
        guard !unratedClips.isEmpty else { return }
        
        isAnalyzing = true
        analysisProgress = 0
        
        Task {
            let results = await AudioAnalyzer.analyzeAndRate(clips: unratedClips)
            
            // Apply suggestions
            var applied: [(UUID, Int)] = []
            for (id, rating) in results {
                if let index = clips.firstIndex(where: { $0.id == id }) {
                    clips[index].suggestedRating = rating
                    applied.append((id, rating))
                }
            }
            
            isAnalyzing = false
            analysisProgress = 1.0
            
            if !applied.isEmpty {
                pushUndo(.audioTriage(suggestions: applied))
            }
        }
    }
    
    /// Accept a single suggestion — promotes to confirmed rating
    func acceptSuggestion(for clipID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }),
              clips[index].hasSuggestion else { return }
        
        let suggested = clips[index].suggestedRating
        clips[index].rating = suggested
        clips[index].suggestedRating = 0
        pushUndo(.acceptSuggestion(clipID: clipID, suggestedRating: suggested))
    }
    
    /// Accept all pending suggestions
    func acceptAllSuggestions() {
        var accepted: [(UUID, Int)] = []
        for index in clips.indices {
            if clips[index].hasSuggestion {
                let suggested = clips[index].suggestedRating
                accepted.append((clips[index].id, suggested))
                clips[index].rating = suggested
                clips[index].suggestedRating = 0
            }
        }
        if !accepted.isEmpty {
            pushUndo(.acceptAllSuggestions(accepted: accepted))
        }
    }
    
    /// Dismiss a single suggestion
    func dismissSuggestion(for clipID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }),
              clips[index].suggestedRating > 0 else { return }
        
        let suggested = clips[index].suggestedRating
        clips[index].suggestedRating = 0
        pushUndo(.dismissSuggestion(clipID: clipID, suggestedRating: suggested))
    }
    
    // MARK: - Undo / Redo
    
    /// Push an undo action (also accessible from views that manage their own operations)
    func pushUndoAction(_ action: UndoAction) {
        pushUndo(action)
    }
    
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
            
        case .audioTriage(let suggestions):
            // Undo = clear all suggestions
            for (id, _) in suggestions {
                if let index = clips.firstIndex(where: { $0.id == id }) {
                    clips[index].suggestedRating = 0
                }
            }
            
        case .acceptSuggestion(let clipID, let suggestedRating):
            // Undo = move rating back to suggestion
            if let index = clips.firstIndex(where: { $0.id == clipID }) {
                clips[index].rating = 0
                clips[index].suggestedRating = suggestedRating
            }
            
        case .acceptAllSuggestions(let accepted):
            // Undo = move all ratings back to suggestions
            for (id, suggestedRating) in accepted {
                if let index = clips.firstIndex(where: { $0.id == id }) {
                    clips[index].rating = 0
                    clips[index].suggestedRating = suggestedRating
                }
            }
            
        case .dismissSuggestion(let clipID, let suggestedRating):
            // Undo = restore suggestion
            if let index = clips.firstIndex(where: { $0.id == clipID }) {
                clips[index].suggestedRating = suggestedRating
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
            
        case .audioTriage(let suggestions):
            for (id, rating) in suggestions {
                if let index = clips.firstIndex(where: { $0.id == id }) {
                    clips[index].suggestedRating = rating
                }
            }
            
        case .acceptSuggestion(let clipID, let suggestedRating):
            if let index = clips.firstIndex(where: { $0.id == clipID }) {
                clips[index].rating = suggestedRating
                clips[index].suggestedRating = 0
            }
            
        case .acceptAllSuggestions(let accepted):
            for (id, rating) in accepted {
                if let index = clips.firstIndex(where: { $0.id == id }) {
                    clips[index].rating = rating
                    clips[index].suggestedRating = 0
                }
            }
            
        case .dismissSuggestion(let clipID, _):
            if let index = clips.firstIndex(where: { $0.id == clipID }) {
                clips[index].suggestedRating = 0
            }
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
    var suggestedClipsCount: Int { clips.filter { $0.hasSuggestion }.count }
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
    
    // MARK: - Export Preview Tree
    
    /// A folder in the export preview tree
    struct ExportFolder: Identifiable {
        let id = UUID()
        let name: String
        let files: [String]
    }
    
    /// Live preview of the export folder structure.
    /// Returns nil when there's nothing to export (no clips with rating or tags).
    var exportPreviewTree: [ExportFolder]? {
        let ratingFolderNames: [Int: String] = [
            5: "5-star",
            4: "4-star",
            3: "3-star",
            2: "2-star",
            1: "1-star",
            0: "Unrated",
        ]
        
        // Only show clips that would be exported (have rating or tags)
        let exportable = clips.filter { $0.effectiveRating > 0 || !$0.tags.isEmpty }
        guard !exportable.isEmpty else { return nil }
        
        // Group by effective rating, sorted highest first
        var grouped: [Int: [String]] = [:]
        for clip in exportable {
            let rating = clip.effectiveRating
            grouped[rating, default: []].append(clip.filename)
        }
        
        // Sort filenames within each group
        for key in grouped.keys {
            grouped[key]?.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        
        // Build folders in descending rating order
        var folders: [ExportFolder] = []
        for rating in stride(from: 5, through: 0, by: -1) {
            guard let files = grouped[rating], !files.isEmpty else { continue }
            let name = ratingFolderNames[rating] ?? "Unrated"
            folders.append(ExportFolder(name: name, files: files))
        }
        
        return folders
    }
    
    /// Count of clips that would be skipped (untouched) on export
    var exportSkippedCount: Int {
        clips.filter { $0.effectiveRating == 0 && $0.tags.isEmpty }.count
    }
    
    // MARK: - Export
    
    /// Export clips to a destination folder, organized by rating
    func exportClips(to baseURL: URL, skipUntouched: Bool) async -> ExportResult {
        let fm = FileManager.default
        
        // Create the RushCut export folder
        let exportFolder = baseURL.appendingPathComponent("RushCut")
        
        // If it already exists, make a unique name
        var finalFolder = exportFolder
        var counter = 1
        while fm.fileExists(atPath: finalFolder.path) {
            finalFolder = baseURL.appendingPathComponent("RushCut \(counter)")
            counter += 1
        }
        
        do {
            try fm.createDirectory(at: finalFolder, withIntermediateDirectories: true)
        } catch {
            return ExportResult(movedCount: 0, skippedCount: 0, errors: ["Failed to create export folder: \(error.localizedDescription)"], exportFolder: nil)
        }
        
        // Determine which clips to export
        let clipsToExport: [Clip]
        let skippedCount: Int
        
        if skipUntouched {
            clipsToExport = clips.filter { $0.effectiveRating > 0 || !$0.tags.isEmpty }
            skippedCount = clips.count - clipsToExport.count
        } else {
            clipsToExport = clips
            skippedCount = 0
        }
        
        // Rating folder names
        let ratingFolderNames: [Int: String] = [
            5: "5-star",
            4: "4-star",
            3: "3-star",
            2: "2-star",
            1: "1-star",
            0: "Unrated",
        ]
        
        // Create rating subfolders as needed
        var neededRatings = Set(clipsToExport.map { $0.rating })
        for rating in neededRatings {
            let folderName = ratingFolderNames[rating] ?? "Unrated"
            let folderURL = finalFolder.appendingPathComponent(folderName)
            try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        
        // Move files
        var movedCount = 0
        var errors: [String] = []
        var exportedClipData: [[String: Any]] = []
        
        for clip in clipsToExport {
            let folderName = ratingFolderNames[clip.effectiveRating] ?? "Unrated"
            let destFolder = finalFolder.appendingPathComponent(folderName)
            var destFile = destFolder.appendingPathComponent(clip.filename)
            
            // Handle filename collisions
            if fm.fileExists(atPath: destFile.path) {
                let stem = destFile.deletingPathExtension().lastPathComponent
                let ext = destFile.pathExtension
                var n = 1
                repeat {
                    destFile = destFolder.appendingPathComponent("\(stem)_\(n).\(ext)")
                    n += 1
                } while fm.fileExists(atPath: destFile.path)
            }
            
            do {
                try fm.moveItem(at: clip.url, to: destFile)
                movedCount += 1
                
                // Build metadata entry
                var entry: [String: Any] = [
                    "filename": destFile.lastPathComponent,
                    "rating": clip.effectiveRating,
                    "tags": Array(clip.tags).sorted(),
                    "duration": round(clip.duration * 10) / 10,
                    "originalPath": clip.url.path,
                    "ratingFolder": folderName,
                ]
                if clip.width > 0 && clip.height > 0 {
                    entry["resolution"] = "\(clip.width)x\(clip.height)"
                }
                if clip.fileSize > 0 {
                    entry["fileSize"] = clip.fileSize
                }
                exportedClipData.append(entry)
            } catch {
                errors.append("\(clip.filename): \(error.localizedDescription)")
            }
        }
        
        // Generate tag summary
        var tagSummary: [String: Int] = [:]
        for clip in clipsToExport {
            for tag in clip.tags {
                tagSummary[tag, default: 0] += 1
            }
        }
        
        // Generate rating summary
        var ratingSummary: [String: Int] = [:]
        for clip in clipsToExport {
            let key = ratingFolderNames[clip.effectiveRating] ?? "Unrated"
            ratingSummary[key, default: 0] += 1
        }
        
        // Write JSON metadata
        let isoFormatter = ISO8601DateFormatter()
        let metadata: [String: Any] = [
            "exportDate": isoFormatter.string(from: Date()),
            "appVersion": "1.0",
            "totalClips": clipsToExport.count,
            "skippedUntouched": skippedCount,
            "ratingSummary": ratingSummary,
            "tagSummary": tagSummary,
            "clips": exportedClipData,
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
            let jsonURL = finalFolder.appendingPathComponent("rushcut.json")
            try? jsonData.write(to: jsonURL)
        }
        
        // Write CSV
        var csv = "Filename,Rating,Tags,Duration,Resolution,Rating Folder,Original Path\n"
        for entry in exportedClipData {
            let filename = entry["filename"] as? String ?? ""
            let rating = entry["rating"] as? Int ?? 0
            let tags = (entry["tags"] as? [String])?.joined(separator: "; ") ?? ""
            let duration = entry["duration"] as? Double ?? 0
            let resolution = entry["resolution"] as? String ?? ""
            let folder = entry["ratingFolder"] as? String ?? ""
            let originalPath = entry["originalPath"] as? String ?? ""
            
            // CSV escape: wrap in quotes if contains comma/quote/newline
            let escapedTags = "\"\(tags.replacingOccurrences(of: "\"", with: "\"\""))\""
            let escapedPath = "\"\(originalPath.replacingOccurrences(of: "\"", with: "\"\""))\""
            
            csv += "\(filename),\(rating),\(escapedTags),\(duration),\(resolution),\(folder),\(escapedPath)\n"
        }
        
        let csvURL = finalFolder.appendingPathComponent("rushcut.csv")
        try? csv.write(to: csvURL, atomically: true, encoding: .utf8)
        
        // Remove moved clips from the store (they're no longer at their original paths)
        let movedIDs = Set(clipsToExport.map { $0.id })
        clips.removeAll { movedIDs.contains($0.id) }
        for clip in clipsToExport {
            loadedURLs.remove(clip.url)
        }
        
        // Also remove untouched clips from store if skipping them
        if skipUntouched {
            let untouched = clips.filter { $0.rating == 0 && $0.tags.isEmpty }
            for clip in untouched {
                loadedURLs.remove(clip.url)
            }
            clips.removeAll { $0.rating == 0 && $0.tags.isEmpty }
        }
        
        return ExportResult(
            movedCount: movedCount,
            skippedCount: skippedCount,
            errors: errors,
            exportFolder: finalFolder
        )
    }
}

// MARK: - Export Result

struct ExportResult {
    let movedCount: Int
    let skippedCount: Int
    let errors: [String]
    let exportFolder: URL?
}
