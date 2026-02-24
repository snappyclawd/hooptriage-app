import Foundation
import SwiftUI

/// Sort options for the clip grid
enum SortOrder: String, CaseIterable {
    case name = "Name"
    case duration = "Duration"
    case rating = "Rating"
}

/// How to organize folders on commit
enum FolderOrganization: String, CaseIterable {
    case byTag = "By Tag"
    case byRating = "By Rating"
}

/// Default basketball tags (alias for built-in defaults from AppSettings)
let defaultTags = builtInDefaultTags

// MARK: - Undo System

/// A single undoable action
enum UndoAction: CustomStringConvertible {
    case setRating(clipID: UUID, oldRating: Int, newRating: Int)
    case toggleTag(clipID: UUID, tag: String, wasAdded: Bool)
    case removeClip(clip: Clip, index: Int)
    case addClips(clipIDs: [UUID])
    case renameClip(clipID: UUID, oldName: String, newName: String)
    /// Bulk tag application from audio triage — stores (clipID, tag) pairs
    case audioTriageTags(applied: [(UUID, String)])
    
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
        case .renameClip(_, _, let newName):
            return "Rename to '\(newName)'"
        case .audioTriageTags(let applied):
            return "Audio Triage (\(applied.count) clips)"
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
    @Published var hideUntouched: Bool = false
    @Published var gridColumns: Int = 3
    @Published var groupMode: GroupMode = .none
    @Published var availableTags: [String] = defaultTags
    @Published var showTagPickerForClipID: UUID? = nil
    @Published var hoveredClipID: UUID? = nil
    @Published var selectedClipIDs: Set<UUID> = []
    @Published var clipToOpen: Clip? = nil
    @Published var renamingClipID: UUID? = nil
    @Published var folderOrganization: FolderOrganization = .byTag
    
    /// The most recently added source folder (used as default commit destination)
    @Published var sourceFolderURL: URL? = nil
    
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
        
        if hideUntouched {
            result = result.filter { $0.rating > 0 || !$0.tags.isEmpty || $0.filename != $0.url.lastPathComponent }
        }
        
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
        sourceFolderURL = url
        
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
    
    /// Toggle a tag on a clip (add if missing, remove if present).
    /// Tags are ordered — first tag added is considered the "primary" tag for folder organization.
    func toggleTag(_ tag: String, for clipID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        if clips[index].tags.contains(tag) {
            clips[index].tags.removeAll { $0 == tag }
            pushUndo(.toggleTag(clipID: clipID, tag: tag, wasAdded: false))
        } else {
            clips[index].tags.append(tag)
            pushUndo(.toggleTag(clipID: clipID, tag: tag, wasAdded: true))
        }
    }
    
    /// Remove a specific tag from a clip
    func removeTag(_ tag: String, for clipID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        if clips[index].tags.contains(tag) {
            clips[index].tags.removeAll { $0 == tag }
            pushUndo(.toggleTag(clipID: clipID, tag: tag, wasAdded: false))
        }
    }
    
    func addTag(_ tag: String) {
        if !availableTags.contains(tag) {
            availableTags.append(tag)
        }
    }
    
    // MARK: - Rename (local state only — applied on disk at commit)
    
    func renameClip(id: UUID, newName: String) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let oldName = clips[index].filename
        guard newName != oldName, !newName.isEmpty else { return }
        
        // Preserve the original extension
        let oldExt = (oldName as NSString).pathExtension
        let newExt = (newName as NSString).pathExtension
        let finalName: String
        if newExt.isEmpty && !oldExt.isEmpty {
            finalName = newName + "." + oldExt
        } else {
            finalName = newName
        }
        
        clips[index].filename = finalName
        pushUndo(.renameClip(clipID: id, oldName: oldName, newName: finalName))
    }
    
    // MARK: - Audio Triage (Loudness Analysis)
    
    /// Cached audio analysis results keyed by clip ID
    @Published var audioMetrics: [UUID: AudioMetrics] = [:]
    
    /// Apply loudness tags from audio triage results
    func applyAudioTriageTags(tags: [(UUID, String)]) {
        var applied: [(UUID, String)] = []
        for (id, tag) in tags {
            guard let index = clips.firstIndex(where: { $0.id == id }) else { continue }
            if !clips[index].tags.contains(tag) {
                clips[index].tags.append(tag)
                applied.append((id, tag))
            }
        }
        if !applied.isEmpty {
            // Ensure tags are in available tags
            let newTags = Set(applied.map { $0.1 })
            for tag in newTags {
                if !availableTags.contains(tag) {
                    availableTags.append(tag)
                }
            }
            pushUndo(.audioTriageTags(applied: applied))
        }
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
                    clips[index].tags.removeAll { $0 == tag }
                } else {
                    clips[index].tags.append(tag)
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
            
        case .renameClip(let clipID, let oldName, _):
            if let index = clips.firstIndex(where: { $0.id == clipID }) {
                clips[index].filename = oldName
            }
            
        case .audioTriageTags(let applied):
            // Undo = remove all the tags that were added
            for (id, tag) in applied {
                if let index = clips.firstIndex(where: { $0.id == id }) {
                    clips[index].tags.removeAll { $0 == tag }
                }
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
                    clips[index].tags.append(tag)
                } else {
                    clips[index].tags.removeAll { $0 == tag }
                }
            }
            
        case .removeClip(let clip, _):
            clips.removeAll { $0.id == clip.id }
            loadedURLs.remove(clip.url)
            
        case .addClips:
            break
            
        case .renameClip(let clipID, _, let newName):
            if let index = clips.firstIndex(where: { $0.id == clipID }) {
                clips[index].filename = newName
            }
            
        case .audioTriageTags(let applied):
            // Redo = re-add all the tags
            for (id, tag) in applied {
                if let index = clips.firstIndex(where: { $0.id == id }) {
                    clips[index].tags.append(tag)
                }
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
    /// Whether audio analysis has been run
    var hasAudioMetrics: Bool { !audioMetrics.isEmpty }
    var taggedClips: Int { clips.filter { !$0.tags.isEmpty }.count }
    var totalDuration: Double { clips.reduce(0) { $0 + $1.duration } }
    
    /// Duration of clips that have been rated or tagged (the "shortlist")
    var shortlistedDuration: Double {
        clips.filter { $0.rating > 0 || !$0.tags.isEmpty }.reduce(0) { $0 + $1.duration }
    }
    
    /// Whether any clips have been triaged (rated or tagged)
    var hasShortlistedClips: Bool {
        clips.contains { $0.rating > 0 || !$0.tags.isEmpty }
    }
    
    var totalDurationFormatted: String {
        formatDuration(totalDuration)
    }
    
    var shortlistedDurationFormatted: String {
        formatDuration(shortlistedDuration)
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        if mins > 60 {
            let hrs = mins / 60
            let remainingMins = mins % 60
            return "\(hrs)h \(remainingMins)m"
        }
        return "\(mins)m \(secs)s"
    }
    
    // MARK: - Folder Preview Tree
    
    /// A single file entry in the folder preview tree
    struct ExportFileEntry: Identifiable {
        var id: String { filename }
        let filename: String
        /// Optional annotation for multi-tag clips, e.g. "also: Defense, Action"
        let annotation: String?
        
        init(_ filename: String, annotation: String? = nil) {
            self.filename = filename
            self.annotation = annotation
        }
    }
    
    /// A folder in the folder preview tree
    struct ExportFolder: Identifiable {
        var id: String { name }
        let name: String
        let files: [ExportFileEntry]
    }
    
    private let ratingFolderNames: [Int: String] = [
        5: "5-star",
        4: "4-star",
        3: "3-star",
        2: "2-star",
        1: "1-star",
        0: "Unrated",
    ]
    
    /// Live preview of the commit folder structure.
    /// Returns nil when there's nothing to commit (no clips with rating or tags).
    var exportPreviewTree: [ExportFolder]? {
        exportPreviewTree(includeUntouched: false)
    }
    
    /// Build export preview tree with option to include untouched clips.
    /// Respects the current `folderOrganization` mode.
    func exportPreviewTree(includeUntouched: Bool) -> [ExportFolder]? {
        let exportable: [Clip]
        if includeUntouched {
            exportable = clips
        } else {
            exportable = clips.filter { $0.rating > 0 || !$0.tags.isEmpty }
        }
        guard !exportable.isEmpty else { return nil }
        
        switch folderOrganization {
        case .byRating:
            return buildRatingPreviewTree(from: exportable)
        case .byTag:
            return buildTagPreviewTree(from: exportable)
        }
    }
    
    /// Build preview tree grouped by star rating (original behavior)
    private func buildRatingPreviewTree(from exportable: [Clip]) -> [ExportFolder] {
        var grouped: [Int: [ExportFileEntry]] = [:]
        for clip in exportable {
            grouped[clip.rating, default: []].append(ExportFileEntry(clip.filename))
        }
        
        // Sort filenames within each group
        for key in grouped.keys {
            grouped[key]?.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
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
    
    /// Build preview tree grouped by first-applied tag.
    /// Tagged clips go into their first tag's folder.
    /// Untagged-but-rated clips fall back to star rating folders.
    private func buildTagPreviewTree(from exportable: [Clip]) -> [ExportFolder] {
        // Separate tagged from untagged
        let tagged = exportable.filter { !$0.tags.isEmpty }
        let untagged = exportable.filter { $0.tags.isEmpty }
        
        // Group tagged clips by their first (primary) tag
        var tagGroups: [String: [ExportFileEntry]] = [:]
        var tagOrder: [String] = [] // preserve first-seen order
        for clip in tagged {
            let primaryTag = clip.tags.first!
            let otherTags = Array(clip.tags.dropFirst())
            let annotation = otherTags.isEmpty ? nil : "also: \(otherTags.joined(separator: ", "))"
            
            if tagGroups[primaryTag] == nil {
                tagOrder.append(primaryTag)
            }
            tagGroups[primaryTag, default: []].append(ExportFileEntry(clip.filename, annotation: annotation))
        }
        
        // Sort filenames within each tag group
        for key in tagGroups.keys {
            tagGroups[key]?.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        }
        
        // Build tag folders in first-seen order
        var folders: [ExportFolder] = []
        for tag in tagOrder {
            guard let files = tagGroups[tag], !files.isEmpty else { continue }
            folders.append(ExportFolder(name: tag, files: files))
        }
        
        // Build rating fallback folders for untagged clips
        if !untagged.isEmpty {
            var ratingGroups: [Int: [ExportFileEntry]] = [:]
            for clip in untagged {
                ratingGroups[clip.rating, default: []].append(ExportFileEntry(clip.filename))
            }
            for key in ratingGroups.keys {
                ratingGroups[key]?.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
            }
            for rating in stride(from: 5, through: 0, by: -1) {
                guard let files = ratingGroups[rating], !files.isEmpty else { continue }
                let name = ratingFolderNames[rating] ?? "Unrated"
                folders.append(ExportFolder(name: name, files: files))
            }
        }
        
        return folders
    }
    
    /// Count of clips that would be skipped (untouched) on commit
    var exportSkippedCount: Int {
        clips.filter { $0.rating == 0 && $0.tags.isEmpty }.count
    }
    
    /// Open a clip in the player modal by filename
    func openClip(byFilename filename: String) {
        if let clip = clips.first(where: { $0.filename == filename }) {
            clipToOpen = clip
        }
    }
    
    // MARK: - Commit
    
    /// Determine the destination folder name for a clip based on the current organization mode.
    /// For byTag: tagged clips go into their first tag's folder, untagged fall back to rating.
    /// For byRating: always use the rating folder.
    private func folderName(for clip: Clip) -> String {
        switch folderOrganization {
        case .byRating:
            return ratingFolderNames[clip.rating] ?? "Unrated"
        case .byTag:
            if let primaryTag = clip.tags.first {
                return primaryTag
            }
            // Untagged clips fall back to star rating folders
            return ratingFolderNames[clip.rating] ?? "Unrated"
        }
    }
    
    // MARK: - Manifest Helpers
    
    /// A planned file move entry in the manifest.
    private struct ManifestEntry {
        let originalPath: String
        let destinationPath: String
        let folder: String
        let expectedSize: Int64
        var status: String // "pending", "moved", "verified", "failed"
        var error: String?
    }
    
    /// Write the manifest JSON to disk. Called before, during, and after the move loop.
    private func writeManifest(
        to url: URL,
        status: String,
        startedAt: String,
        entries: [ManifestEntry]
    ) {
        let entriesData: [[String: Any]] = entries.map { entry in
            var dict: [String: Any] = [
                "from": entry.originalPath,
                "to": entry.destinationPath,
                "folder": entry.folder,
                "expectedSize": entry.expectedSize,
                "status": entry.status,
            ]
            if let error = entry.error {
                dict["error"] = error
            }
            return dict
        }
        
        let manifest: [String: Any] = [
            "status": status,
            "startedAt": startedAt,
            "organization": folderOrganization.rawValue,
            "totalPlanned": entries.count,
            "moved": entries.filter { $0.status == "moved" || $0.status == "verified" }.count,
            "verified": entries.filter { $0.status == "verified" }.count,
            "failed": entries.filter { $0.status == "failed" }.count,
            "pending": entries.filter { $0.status == "pending" }.count,
            "files": entriesData,
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
    
    /// Commit clips to a destination folder, organized by rating or tag.
    ///
    /// Safety guarantees:
    /// 1. A `rushcut-manifest.json` is written BEFORE any files are moved, recording every planned operation.
    /// 2. The manifest is updated after each file move with its current status.
    /// 3. After each move, the destination file is verified (exists + size matches).
    /// 4. If verification fails, the error is recorded and the clip is not removed from the store.
    /// 5. Final metadata (rushcut.json, rushcut.csv) is written only for successfully verified files.
    func exportClips(to baseURL: URL, skipUntouched: Bool) async -> ExportResult {
        let fm = FileManager.default
        let isoFormatter = ISO8601DateFormatter()
        let startedAt = isoFormatter.string(from: Date())
        
        // Create the RushCut folder
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
            clipsToExport = clips.filter { $0.rating > 0 || !$0.tags.isEmpty }
            skippedCount = clips.count - clipsToExport.count
        } else {
            clipsToExport = clips
            skippedCount = 0
        }
        
        // Determine needed subfolders and create them
        let neededFolders = Set(clipsToExport.map { folderName(for: $0) })
        for folder in neededFolders {
            let folderURL = finalFolder.appendingPathComponent(folder)
            try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        
        // --- SAFETY: Build manifest with all planned moves ---
        let manifestURL = finalFolder.appendingPathComponent("rushcut-manifest.json")
        
        // Pre-compute destination paths (with collision handling) for the manifest
        var manifestEntries: [ManifestEntry] = []
        var usedDestPaths: Set<String> = []
        
        for clip in clipsToExport {
            let destFolderName = folderName(for: clip)
            let destFolder = finalFolder.appendingPathComponent(destFolderName)
            var destFile = destFolder.appendingPathComponent(clip.filename)
            
            // Handle filename collisions (both existing files AND earlier entries in this batch)
            if fm.fileExists(atPath: destFile.path) || usedDestPaths.contains(destFile.path) {
                let stem = destFile.deletingPathExtension().lastPathComponent
                let ext = destFile.pathExtension
                var n = 1
                repeat {
                    destFile = destFolder.appendingPathComponent("\(stem)_\(n).\(ext)")
                    n += 1
                } while fm.fileExists(atPath: destFile.path) || usedDestPaths.contains(destFile.path)
            }
            
            usedDestPaths.insert(destFile.path)
            
            manifestEntries.append(ManifestEntry(
                originalPath: clip.url.path,
                destinationPath: destFile.path,
                folder: destFolderName,
                expectedSize: clip.fileSize,
                status: "pending"
            ))
        }
        
        // Write the initial manifest BEFORE moving anything
        writeManifest(to: manifestURL, status: "in_progress", startedAt: startedAt, entries: manifestEntries)
        
        // --- Move files with verification ---
        var movedCount = 0
        var errors: [String] = []
        var exportedClipData: [[String: Any]] = []
        var successfullyMovedClipIDs: Set<UUID> = []
        
        for (i, clip) in clipsToExport.enumerated() {
            let entry = manifestEntries[i]
            let destFile = URL(fileURLWithPath: entry.destinationPath)
            let destFolderName = entry.folder
            
            do {
                // Move the file
                try fm.moveItem(at: clip.url, to: destFile)
                
                // --- SAFETY: Verify the move ---
                // Check destination exists
                guard fm.fileExists(atPath: destFile.path) else {
                    manifestEntries[i].status = "failed"
                    manifestEntries[i].error = "File not found at destination after move"
                    errors.append("\(clip.filename): File not found at destination after move")
                    writeManifest(to: manifestURL, status: "in_progress", startedAt: startedAt, entries: manifestEntries)
                    continue
                }
                
                // Check file size matches (if we have the expected size)
                if clip.fileSize > 0 {
                    if let attrs = try? fm.attributesOfItem(atPath: destFile.path),
                       let actualSize = attrs[FileAttributeKey.size] as? Int64 {
                        if actualSize != clip.fileSize {
                            manifestEntries[i].status = "failed"
                            manifestEntries[i].error = "Size mismatch: expected \(clip.fileSize), got \(actualSize)"
                            errors.append("\(clip.filename): Size mismatch after move (expected \(clip.fileSize), got \(actualSize))")
                            writeManifest(to: manifestURL, status: "in_progress", startedAt: startedAt, entries: manifestEntries)
                            continue
                        }
                    }
                }
                
                // Verification passed
                manifestEntries[i].status = "verified"
                movedCount += 1
                successfullyMovedClipIDs.insert(clip.id)
                
                // Build metadata entry (only for verified moves)
                var metaEntry: [String: Any] = [
                    "filename": destFile.lastPathComponent,
                    "rating": clip.rating,
                    "tags": clip.tags.sorted(),
                    "duration": round(clip.duration * 10) / 10,
                    "originalPath": clip.url.path,
                    "folder": destFolderName,
                    "ratingFolder": ratingFolderNames[clip.rating] ?? "Unrated",
                    "organization": folderOrganization.rawValue,
                ]
                if folderOrganization == .byTag && !clip.tags.isEmpty {
                    metaEntry["primaryTag"] = clip.tags.first
                    metaEntry["tagFolder"] = destFolderName
                }
                if clip.width > 0 && clip.height > 0 {
                    metaEntry["resolution"] = "\(clip.width)x\(clip.height)"
                }
                if clip.fileSize > 0 {
                    metaEntry["fileSize"] = clip.fileSize
                }
                exportedClipData.append(metaEntry)
                
            } catch {
                manifestEntries[i].status = "failed"
                manifestEntries[i].error = error.localizedDescription
                errors.append("\(clip.filename): \(error.localizedDescription)")
            }
            
            // Update manifest after each file (so it's always current if the app crashes)
            writeManifest(to: manifestURL, status: "in_progress", startedAt: startedAt, entries: manifestEntries)
        }
        
        // --- Finalize manifest ---
        let finalStatus = errors.isEmpty ? "complete" : "complete_with_errors"
        writeManifest(to: manifestURL, status: finalStatus, startedAt: startedAt, entries: manifestEntries)
        
        // --- Write final metadata (only includes verified files) ---
        
        // Generate tag summary
        var tagSummary: [String: Int] = [:]
        for clip in clipsToExport where successfullyMovedClipIDs.contains(clip.id) {
            for tag in clip.tags {
                tagSummary[tag, default: 0] += 1
            }
        }
        
        // Generate rating summary
        var ratingSummary: [String: Int] = [:]
        for clip in clipsToExport where successfullyMovedClipIDs.contains(clip.id) {
            let key = ratingFolderNames[clip.rating] ?? "Unrated"
            ratingSummary[key, default: 0] += 1
        }
        
        // Write JSON metadata
        let metadata: [String: Any] = [
            "exportDate": startedAt,
            "appVersion": "1.0",
            "totalClips": movedCount,
            "skippedUntouched": skippedCount,
            "organization": folderOrganization.rawValue,
            "ratingSummary": ratingSummary,
            "tagSummary": tagSummary,
            "clips": exportedClipData,
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
            let jsonURL = finalFolder.appendingPathComponent("rushcut.json")
            try? jsonData.write(to: jsonURL)
        }
        
        // Write CSV
        var csv = "Filename,Rating,Tags,Duration,Resolution,Folder,Rating Folder,Original Path\n"
        for entry in exportedClipData {
            let filename = entry["filename"] as? String ?? ""
            let rating = entry["rating"] as? Int ?? 0
            let tags = (entry["tags"] as? [String])?.joined(separator: "; ") ?? ""
            let duration = entry["duration"] as? Double ?? 0
            let resolution = entry["resolution"] as? String ?? ""
            let folder = entry["folder"] as? String ?? ""
            let ratingFolder = entry["ratingFolder"] as? String ?? ""
            let originalPath = entry["originalPath"] as? String ?? ""
            
            // CSV escape: wrap in quotes if contains comma/quote/newline
            let escapedTags = "\"\(tags.replacingOccurrences(of: "\"", with: "\"\""))\""
            let escapedPath = "\"\(originalPath.replacingOccurrences(of: "\"", with: "\"\""))\""
            
            csv += "\(filename),\(rating),\(escapedTags),\(duration),\(resolution),\(folder),\(ratingFolder),\(escapedPath)\n"
        }
        
        let csvURL = finalFolder.appendingPathComponent("rushcut.csv")
        try? csv.write(to: csvURL, atomically: true, encoding: .utf8)
        
        // --- Clean up store: only remove clips that were successfully verified ---
        clips.removeAll { successfullyMovedClipIDs.contains($0.id) }
        for clip in clipsToExport where successfullyMovedClipIDs.contains(clip.id) {
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
