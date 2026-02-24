import SwiftUI

/// Commit sheet — lets user choose destination and options before committing triage to disk
struct ExportView: View {
    @ObservedObject var store: ClipStore
    @EnvironmentObject var settings: AppSettings
    let onDismiss: () -> Void
    
    @State private var exportURL: URL? = nil
    @State private var removeUntouched = true
    @State private var isExporting = false
    @State private var exportResult: ExportResult? = nil
    
    /// Default to the source folder so a RushCut directory is created alongside the footage
    private var initialURL: URL? { store.sourceFolderURL }
    
    /// Clips that have been rated or tagged
    private var touchedClips: [Clip] {
        store.clips.filter { $0.rating > 0 || !$0.tags.isEmpty }
    }
    
    /// Clips with no rating and no tags
    private var untouchedClips: [Clip] {
        store.clips.filter { $0.rating == 0 && $0.tags.isEmpty }
    }
    
    /// Clips that will be exported based on current settings
    private var clipsToExport: [Clip] {
        removeUntouched ? touchedClips : store.clips
    }
    
    /// Whether the chosen destination is on a different volume than the source footage.
    /// Cross-volume moves are actually copy+delete operations — slower and riskier.
    private var isCrossVolume: Bool {
        guard let sourceURL = store.sourceFolderURL,
              let destURL = exportURL else { return false }
        let sourceVolume = try? sourceURL.resourceValues(forKeys: [URLResourceKey.volumeIdentifierKey]).volumeIdentifier as? NSObject
        let destVolume = try? destURL.resourceValues(forKeys: [URLResourceKey.volumeIdentifierKey]).volumeIdentifier as? NSObject
        guard let sv = sourceVolume, let dv = destVolume else { return false }
        return sv != dv
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Commit RushCut Folder")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            if let result = exportResult {
                // Export complete
                exportCompleteView(result)
            } else {
                // Export options
                exportOptionsView
            }
        }
        .frame(width: 500)
        .background(.regularMaterial)
        .cornerRadius(12)
        .onAppear {
            if exportURL == nil {
                exportURL = initialURL
            }
        }
    }
    
    // MARK: - Commit Options
    
    private var exportOptionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Summary")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 20) {
                    summaryItem("\(store.clips.count)", label: "total clips")
                    summaryItem("\(touchedClips.count)", label: "rated/tagged")
                    summaryItem("\(untouchedClips.count)", label: "untouched")
                }
            }
            
            Divider()
            
            // Destination
            VStack(alignment: .leading, spacing: 8) {
                Text("Destination")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack {
                    if let url = exportURL {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                        Text(url.path)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundColor(.primary)
                    } else {
                        Text("No destination selected")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Choose…") {
                        pickExportFolder()
                    }
                }
                
                Text("A \"RushCut\" folder will be created here with your triaged clips.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                
                // Cross-volume warning
                if isCrossVolume {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Different volume detected")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.orange)
                            Text("The destination is on a different drive than your footage. Files will be **copied** (not moved), which is much slower for large video files and carries more risk if interrupted.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("For instant, safe commits — keep the destination on the same drive as your footage.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary.opacity(0.8))
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                    )
                }
            }
            
            Divider()
            
            // Options
            VStack(alignment: .leading, spacing: 10) {
                Text("Options")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                // Folder organization mode
                VStack(alignment: .leading, spacing: 6) {
                    Text("Organize folders by")
                        .font(.system(size: 13))
                    
                    Picker("", selection: $store.folderOrganization) {
                        ForEach(FolderOrganization.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    
                    Text(store.folderOrganization == .byRating
                         ? "Clips sorted into 5-star, 4-star, etc. folders"
                         : "Clips sorted into folders by their first tag. Untagged clips fall back to star rating folders.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Toggle(isOn: $removeUntouched) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip untouched clips")
                            .font(.system(size: 13))
                        Text("Clips with no rating and no tags stay in their original location")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            
            Divider()
            
            // Folder Preview
            if let tree = store.exportPreviewTree(includeUntouched: !removeUntouched) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Folder Preview")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        // Root folder
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11))
                                .foregroundColor(settings.accent)
                            Text("RushCut/")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        
                        // Subfolders (rating or tag based)
                        ForEach(tree) { folder in
                            ExportTreeFolderRow(folder: folder) { filename in
                                store.openClip(byFilename: filename)
                            }
                            .padding(.leading, 14)
                        }
                        
                        // Metadata files
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("rushcut.json")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 14)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("rushcut.csv")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 14)
                    }
                    
                    // Multi-tag notice for tag mode
                    if store.folderOrganization == .byTag {
                        let multiTagCount = clipsToExport.filter { $0.tags.count > 1 }.count
                        if multiTagCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue)
                                Text("\(multiTagCount) clip\(multiTagCount == 1 ? " has" : "s have") multiple tags — placed in first tag's folder. All tags are preserved in the metadata.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                
                Divider()
            }
            
            // What will happen
            VStack(alignment: .leading, spacing: 6) {
                Text("What will happen")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Label(
                    "\(clipsToExport.count) clips will be **\(isCrossVolume ? "copied" : "moved")** into \(store.folderOrganization == .byRating ? "rating" : "tag") folders",
                    systemImage: "folder.badge.plus"
                )
                    .font(.system(size: 12))
                
                if removeUntouched && untouchedClips.count > 0 {
                    Label("\(untouchedClips.count) untouched clips left in place", systemImage: "film")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Label("Metadata files generated (JSON + CSV)", systemImage: "doc.text")
                    .font(.system(size: 12))
                
                Label(
                    isCrossVolume
                        ? "Original files are **copied** to the other volume (slower)"
                        : "Original files are **moved**, not copied (instant)",
                    systemImage: isCrossVolume ? "doc.on.doc" : "arrow.right"
                )
                    .font(.system(size: 12))
                    .foregroundColor(settings.accent)
            }
            
            Spacer()
            
            // Export button
            HStack {
                Spacer()
                
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(action: {
                    startExport()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Commit \(clipsToExport.count) Clips")
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(settings.accent)
                .disabled(exportURL == nil || clipsToExport.isEmpty || isExporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
    
    // MARK: - Commit Complete
    
    private func exportCompleteView(_ result: ExportResult) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: result.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(result.errors.isEmpty ? .green : .orange)
            
            Text(result.errors.isEmpty ? "Commit Complete!" : "Commit Finished with Issues")
                .font(.system(size: 16, weight: .semibold))
            
            VStack(spacing: 4) {
                Text("\(result.movedCount) clips moved")
                    .font(.system(size: 13))
                if result.skippedCount > 0 {
                    Text("\(result.skippedCount) untouched clips left in place")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                if !result.errors.isEmpty {
                    Text("\(result.errors.count) errors")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            HStack {
                if let url = result.exportFolder {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                }
                
                Spacer()
                
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
    
    // MARK: - Actions
    
    private func pickExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to create the RushCut folder"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK {
            exportURL = panel.url
        }
    }
    
    private func startExport() {
        guard let baseURL = exportURL else { return }
        isExporting = true
        
        Task {
            let result = await store.exportClips(
                to: baseURL,
                skipUntouched: removeUntouched
            )
            isExporting = false
            exportResult = result
        }
    }
    
    private func summaryItem(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
