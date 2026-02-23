import SwiftUI

/// Export sheet — lets user choose destination and options before exporting
struct ExportView: View {
    @ObservedObject var store: ClipStore
    let onDismiss: () -> Void
    
    @State private var exportURL: URL? = nil
    @State private var removeUntouched = true
    @State private var isExporting = false
    @State private var exportResult: ExportResult? = nil
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Triage")
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
    }
    
    // MARK: - Export Options
    
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
                
                Text("A \"RushCut\" folder will be created inside.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Divider()
            
            // Options
            VStack(alignment: .leading, spacing: 10) {
                Text("Options")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
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
            
            // What will happen
            VStack(alignment: .leading, spacing: 6) {
                Text("What will happen")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Label("\(clipsToExport.count) clips will be **moved** into rating folders", systemImage: "folder.badge.plus")
                    .font(.system(size: 12))
                
                if removeUntouched && untouchedClips.count > 0 {
                    Label("\(untouchedClips.count) untouched clips left in place", systemImage: "film")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Label("Metadata files generated (JSON + CSV)", systemImage: "doc.text")
                    .font(.system(size: 12))
                
                Label("Original files are **moved**, not copied", systemImage: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
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
                        Image(systemName: "square.and.arrow.up")
                        Text("Export \(clipsToExport.count) Clips")
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(exportURL == nil || clipsToExport.isEmpty || isExporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
    
    // MARK: - Export Complete
    
    private func exportCompleteView(_ result: ExportResult) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: result.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(result.errors.isEmpty ? .green : .orange)
            
            Text(result.errors.isEmpty ? "Export Complete!" : "Export Finished with Issues")
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
        panel.message = "Choose where to create the RushCut export folder"
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
