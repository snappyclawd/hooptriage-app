import SwiftUI
import UniformTypeIdentifiers

/// Main app view
struct ContentView: View {
    @StateObject private var store = ClipStore()
    @State private var isDragTargeted = false
    @State private var audioEnabled = false
    
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            
            if !store.clips.isEmpty && !store.usedTags.isEmpty {
                tagFilterBar
                Divider()
            }
            
            if store.clips.isEmpty && !store.isLoading {
                dropZone
            } else {
                ClipGridView(store: store, audioEnabled: audioEnabled)
            }
            
            if store.isLoading {
                ProgressView(value: store.loadingProgress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("🏀")
                    .font(.title2)
                Text("HoopTriage")
                    .font(.headline)
            }
            
            if !store.clips.isEmpty {
                HStack(spacing: 12) {
                    statBadge("\(store.totalClips)", label: "clips")
                    statBadge("\(store.ratedClips)", label: "rated")
                    statBadge("\(store.taggedClips)", label: "tagged")
                    statBadge(store.totalDurationFormatted, label: "footage")
                }
                .font(.system(size: 12))
            }
            
            Spacer()
            
            if !store.clips.isEmpty {
                // Audio toggle
                Button(action: { audioEnabled.toggle() }) {
                    Image(systemName: audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(audioEnabled ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(audioEnabled ? "Mute scrub audio" : "Enable scrub audio")
                
                // Rating filter
                Picker("", selection: $store.filterRating) {
                    Text("All").tag(0)
                    ForEach(1...5, id: \.self) { r in
                        Text("\(r)★").tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                
                // Sort
                Picker("Sort", selection: $store.sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .frame(width: 110)
                
                // Group toggle
                Picker("Group", selection: $store.groupMode) {
                    ForEach(GroupMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(width: 130)
                
                // Grid size slider (1-5 columns, small left, big right)
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.4x3.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                    Slider(value: Binding(
                        get: { Double(6 - store.gridColumns) },
                        set: { store.gridColumns = max(1, min(5, 6 - Int($0))) }
                    ), in: 1...5, step: 1)
                    .frame(width: 80)
                    Image(systemName: "square")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                }
            }
            
            Button(action: { store.pickFolder() }) {
                Label("Open Folder", systemImage: "folder")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Tag Filter Bar
    
    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Tags:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Button(action: { store.filterTag = nil }) {
                    Text("All")
                        .font(.system(size: 11, weight: store.filterTag == nil ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(store.filterTag == nil ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                ForEach(store.usedTags, id: \.self) { tag in
                    Button(action: {
                        store.filterTag = store.filterTag == tag ? nil : tag
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(tagColor(for: tag))
                                .frame(width: 6, height: 6)
                            Text(tag)
                                .font(.system(size: 11, weight: store.filterTag == tag ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(store.filterTag == tag ? tagColor(for: tag).opacity(0.15) : Color.clear)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
    
    private func statBadge(_ value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .fontWeight(.semibold)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Drop Zone
    
    private var dropZone: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundColor(isDragTargeted ? .accentColor : .secondary)
            
            Text("Drop a folder of clips here")
                .font(.title2)
                .foregroundColor(isDragTargeted ? .accentColor : .primary)
            
            Text("or")
                .foregroundColor(.secondary)
            
            Button(action: { store.pickFolder() }) {
                Label("Choose Folder", systemImage: "folder")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            
            Text("Supports MOV, MP4, AVI, MKV and more")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .padding(40)
        )
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
                        // Dropped a folder — load it (handles nested folders + ignores non-video files)
                        store.loadFolder(url)
                    } else {
                        // Dropped individual file(s) — load the parent folder
                        // or add individual clips
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
