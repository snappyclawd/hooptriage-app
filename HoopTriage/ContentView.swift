import SwiftUI
import UniformTypeIdentifiers

/// Main app view
struct ContentView: View {
    @StateObject private var store = ClipStore()
    @State private var isDragTargeted = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
            
            Divider()
            
            if store.clips.isEmpty && !store.isLoading {
                // Drop zone
                dropZone
            } else {
                // Clip grid
                ClipGridView(store: store)
            }
            
            // Loading bar
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
            // App title
            HStack(spacing: 6) {
                Text("🏀")
                    .font(.title2)
                Text("HoopTriage")
                    .font(.headline)
            }
            
            // Stats
            if !store.clips.isEmpty {
                HStack(spacing: 12) {
                    statBadge("\(store.totalClips)", label: "clips")
                    statBadge("\(store.ratedClips)", label: "rated")
                    statBadge(store.totalDurationFormatted, label: "footage")
                }
                .font(.system(size: 12))
            }
            
            Spacer()
            
            // Controls
            if !store.clips.isEmpty {
                // Filter by rating
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
                
                // Grid size slider
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.3x3")
                        .foregroundColor(.secondary)
                    Slider(value: Binding(
                        get: { Double(store.gridColumns) },
                        set: { store.gridColumns = max(1, min(8, Int($0))) }
                    ), in: 1...8, step: 1)
                    .frame(width: 80)
                }
            }
            
            // Open folder button
            Button(action: { store.pickFolder() }) {
                Label("Open Folder", systemImage: "folder")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return }
            
            DispatchQueue.main.async {
                store.loadFolder(url)
            }
        }
        
        return true
    }
}
