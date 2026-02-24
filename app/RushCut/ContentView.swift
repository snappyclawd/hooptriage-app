import SwiftUI
import UniformTypeIdentifiers

/// Main app view — slim top bar + collapsible sidebar + clip grid.
struct ContentView: View {
    @EnvironmentObject var store: ClipStore
    @EnvironmentObject var settings: AppSettings
    @State private var isDragTargeted = false
    @State private var audioEnabled = false
    @State private var showCommit = false
    @State private var showAudioTriage = false
    @State private var sidebarVisible = true
    
    private let sidebarWidth: CGFloat = 240
    
    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            
            HStack(spacing: 0) {
                // Collapsible sidebar
                if sidebarVisible, !store.clips.isEmpty {
                    sidebar
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    
                    Divider()
                }
                
                // Main content
                VStack(spacing: 0) {
                    if store.clips.isEmpty && !store.isLoading {
                        dropZone
                    } else {
                        ClipGridView(store: store, audioEnabled: audioEnabled)
                    }
                    
                    if store.isLoading {
                        ProgressView(value: store.loadingProgress)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $showCommit) {
            ExportView(store: store) {
                showCommit = false
            }
        }
        .sheet(isPresented: $showAudioTriage) {
            AudioTriageView(store: store) {
                showAudioTriage = false
            }
        }
        .animation(.easeInOut(duration: 0.2), value: sidebarVisible)
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack(spacing: 12) {
            // Sidebar toggle
            if !store.clips.isEmpty {
                Button(action: { sidebarVisible.toggle() }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(sidebarVisible ? "Hide sidebar" : "Show sidebar")
            }
            
            // Logo
            HStack(spacing: 6) {
                RushCutLogo(size: 20)
                Text("RushCut")
                    .font(.system(size: 16, weight: .bold))
            }
            
            // Stats
            if !store.clips.isEmpty {
                Divider().frame(height: 20)
                
                HStack(spacing: 14) {
                    statBadge("\(store.totalClips)", label: "clips")
                    statBadge("\(store.ratedClips)", label: "rated")
                    statBadge("\(store.taggedClips)", label: "tagged")
                    if store.hasShortlistedClips {
                        HStack(spacing: 4) {
                            Text(store.shortlistedDurationFormatted)
                                .fontWeight(.semibold)
                            Text("shortlisted")
                                .foregroundColor(.secondary)
                            Text("(\(store.totalDurationFormatted) total)")
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .fixedSize()
                    } else {
                        statBadge(store.totalDurationFormatted, label: "footage")
                    }
                }
                .font(.system(size: 12))
            }
            
            Spacer()
            
            // Undo / Redo
            if !store.undoStack.isEmpty || !store.redoStack.isEmpty {
                HStack(spacing: 4) {
                    Button(action: { store.undo() }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.undoStack.isEmpty)
                    .help(store.undoDescription ?? "Nothing to undo")
                    .foregroundColor(store.undoStack.isEmpty ? .secondary.opacity(0.3) : .secondary)
                    
                    Button(action: { store.redo() }) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.redoStack.isEmpty)
                    .help(store.redoDescription ?? "Nothing to redo")
                    .foregroundColor(store.redoStack.isEmpty ? .secondary.opacity(0.3) : .secondary)
                }
            }
            
            Button(action: { store.pickFolder() }) {
                Label("Add Footage", systemImage: "plus.rectangle.on.folder")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(spacing: 0) {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                
                // MARK: Filter
                sidebarSection("Filter") {
                    // Rating filter
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rating")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 2) {
                            sidebarFilterButton(label: "All", isActive: store.filterRating == 0) {
                                store.filterRating = 0
                            }
                            ForEach(Array(stride(from: 5, through: 1, by: -1)), id: \.self) { r in
                                sidebarFilterButton(
                                    label: "\(r) \(String(repeating: "★", count: r))",
                                    isActive: store.filterRating == r
                                ) {
                                    store.filterRating = store.filterRating == r ? 0 : r
                                }
                            }
                        }
                    }
                    
                    // Hide untouched
                    HStack {
                        Image(systemName: store.hideUntouched ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        Text("Hide untouched")
                            .font(.system(size: 12))
                        Spacer()
                        Toggle("", isOn: $store.hideUntouched)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                    
                    // Tag filter
                    if !store.usedTags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tags")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 2) {
                                sidebarFilterButton(label: "All", isActive: store.filterTag == nil) {
                                    store.filterTag = nil
                                }
                                ForEach(store.usedTags, id: \.self) { tag in
                                    sidebarFilterButton(
                                        label: tag,
                                        color: tagColor(for: tag),
                                        isActive: store.filterTag == tag
                                    ) {
                                        store.filterTag = store.filterTag == tag ? nil : tag
                                    }
                                }
                            }
                        }
                    }
                }
                
                sidebarDivider
                
                // MARK: Sort & Group
                sidebarSection("Sort & Group") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sort by")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Picker("", selection: $store.sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Group by")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Picker("", selection: $store.groupMode) {
                            ForEach(GroupMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
                
                sidebarDivider
                
                // MARK: View
                sidebarSection("View") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Grid size")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: "square.grid.4x3.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                            Slider(value: Binding(
                                get: { Double(6 - store.gridColumns) },
                                set: { store.gridColumns = max(1, min(5, 6 - Int($0))) }
                            ), in: 1...5, step: 1)
                            Image(systemName: "square")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                        }
                    }
                    
                    // Audio toggle
                    HStack {
                        Image(systemName: audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 12))
                            .foregroundColor(audioEnabled ? .accentColor : .secondary)
                            .frame(width: 16)
                        Text("Scrub audio")
                            .font(.system(size: 12))
                        Spacer()
                        Toggle("", isOn: $audioEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                }
                
                sidebarDivider
                
                // MARK: Tools
                sidebarSection("Tools") {
                    Button(action: { showAudioTriage = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .frame(width: 16)
                            Text("Audio Triage")
                            Spacer()
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 16)
        }
        
        // MARK: Folder Preview (pinned above commit)
        if let tree = store.exportPreviewTree {
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Folder Preview")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    // Compact organization mode picker
                    Picker("", selection: $store.folderOrganization) {
                        Image(systemName: "tag.fill").tag(FolderOrganization.byTag)
                        Image(systemName: "star.fill").tag(FolderOrganization.byRating)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 60)
                    .controlSize(.mini)
                    .help(store.folderOrganization == .byRating ? "Organize by star rating" : "Organize by tag")
                }
                
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
                
                // Summary
                if store.exportSkippedCount > 0 {
                    Text("\(store.exportSkippedCount) untouched clip\(store.exportSkippedCount == 1 ? "" : "s") will be skipped")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
            
        // MARK: Commit CTA (pinned to bottom)
        Divider()
            
        Button(action: { showCommit = true }) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                Text("Commit")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(.white)
            .background(
                LinearGradient(
                    colors: [settings.accent, settings.accent.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Sidebar Components
    
    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            content()
        }
        .padding(.vertical, 12)
    }
    
    private var sidebarDivider: some View {
        Divider()
    }
    
    private func sidebarFilterButton(label: String, color: Color? = nil, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helpers
    
    private func statBadge(_ value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .fontWeight(.semibold)
            Text(label)
                .foregroundColor(.secondary)
        }
        .fixedSize()
    }
    
    // MARK: - Drop Zone
    
    @State private var heroAnimating = false
    
    private var dropZone: some View {
        ZStack {
            // Adaptive background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Hero section
                VStack(spacing: 32) {
                    // Animated icon cluster
                    ZStack {
                        // Background glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [settings.accent.opacity(0.15), Color.clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 160, height: 160)
                            .scaleEffect(heroAnimating ? 1.1 : 0.95)
                            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: heroAnimating)
                        
                        // Main icon
                        RushCutLogo(size: 56)
                            .scaleEffect(isDragTargeted ? 1.15 : 1.0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isDragTargeted)
                    }
                    
                    // Headlines
                    VStack(spacing: 10) {
                        Text("Stop drowning in footage")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("Scrub, rate, tag, and organize. Manually, or audio-based.")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    
                    // Drop area card
                    VStack(spacing: 20) {
                        // Main CTA
                        Button(action: { store.pickFolder() }) {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 18))
                                Text("Choose Footage")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [settings.accent, settings.accent.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: settings.accent.opacity(0.3), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                        
                        // Divider with "or"
                        HStack {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 1)
                            Text("or drag & drop")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .fixedSize()
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 1)
                        }
                        .frame(maxWidth: 280)
                        
                        // Drop target area
                        VStack(spacing: 8) {
                            Image(systemName: isDragTargeted ? "arrow.down.circle.fill" : "arrow.down.circle.dotted")
                                .font(.system(size: 28))
                                .foregroundColor(isDragTargeted ? settings.accent : .secondary.opacity(0.4))
                                .scaleEffect(isDragTargeted ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3), value: isDragTargeted)
                            
                            Text("Drop folders or video files here")
                                .font(.system(size: 13))
                                .foregroundColor(isDragTargeted ? settings.accent : .secondary.opacity(0.6))
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 40)
                        .frame(maxWidth: 360)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isDragTargeted ? settings.accent : Color.secondary.opacity(0.15),
                                    style: StrokeStyle(lineWidth: isDragTargeted ? 2 : 1.5, dash: [8, 4])
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isDragTargeted ? settings.accent.opacity(0.05) : Color.clear)
                                )
                        )
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .primary.opacity(0.08), radius: 24, y: 8)
                    )
                    .frame(maxWidth: 440)
                }
                
                Spacer()
                
                // Bottom features strip
                HStack(spacing: 40) {
                    featureItem(icon: "hand.draw", title: "Scrub & Preview", desc: "Hover to preview clips instantly")
                    featureItem(icon: "star", title: "Quick Rate", desc: "1-5 keyboard shortcuts")
                    featureItem(icon: "tag", title: "Multi-Tag", desc: "Organize by plays, drills & more")
                    featureItem(icon: "checkmark.circle", title: "Commit", desc: "Sorted folders by rating")
                }
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { heroAnimating = true }
    }
    
    private func featureItem(icon: String, title: String, desc: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(settings.accent.opacity(0.7))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 140)
    }
    
    // MARK: - Drop handling
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                
                DispatchQueue.main.async {
                    if isDir.boolValue {
                        // Dropped a folder — add clips (additive, skips duplicates)
                        store.addFolder(url)
                    } else {
                        // Dropped individual file(s) — add to collection
                        let ext = url.pathExtension.lowercased()
                        if supportedExtensions.contains(ext) {
                            store.addClip(url: url)
                        }
                    }
                }
            }
        }
        return true
    }
    
    private func tagColor(for tag: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .teal, .indigo, .mint, .cyan]
        let hash = abs(tag.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Folder Preview Tree Row

/// A collapsible folder row in the folder preview tree.
struct ExportTreeFolderRow: View {
    let folder: ClipStore.ExportFolder
    var onOpenFile: ((String) -> Void)? = nil
    @State private var expanded = false
    
    /// Max files to show before collapsing with a "and N more..." label
    private let previewLimit = 4
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Folder header — tap to expand/collapse
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .frame(width: 8)
                    Image(systemName: expanded ? "folder.fill" : "folder")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text("\(folder.name)/")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("(\(folder.files.count))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            // Expanded file list
            if expanded {
                let filesToShow = folder.files.prefix(previewLimit)
                let remaining = folder.files.count - filesToShow.count
                
                ForEach(Array(filesToShow.enumerated()), id: \.offset) { _, entry in
                    fileRow(entry)
                }
                
                if remaining > 0 {
                    Text("and \(remaining) more...")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                        .italic()
                        .padding(.leading, 20)
                }
            }
        }
    }
    
    @ViewBuilder
    private func fileRow(_ entry: ClipStore.ExportFileEntry) -> some View {
        if let onOpenFile {
            Button(action: { onOpenFile(entry.filename) }) {
                fileRowContent(entry)
            }
            .buttonStyle(.plain)
        } else {
            fileRowContent(entry)
        }
    }
    
    private func fileRowContent(_ entry: ClipStore.ExportFileEntry) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "film")
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.6))
            Text(entry.filename)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(onOpenFile != nil ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let annotation = entry.annotation {
                Text("(\(annotation))")
                    .font(.system(size: 8))
                    .foregroundColor(.blue.opacity(0.7))
                    .lineLimit(1)
            }
            if onOpenFile != nil {
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(.leading, 20)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}
