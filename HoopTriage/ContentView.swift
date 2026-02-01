import SwiftUI
import UniformTypeIdentifiers

/// Main app view
struct ContentView: View {
    @EnvironmentObject var store: ClipStore
    @State private var isDragTargeted = false
    @State private var audioEnabled = false
    @State private var showExport = false
    @State private var showAudioTriage = false
    
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $showExport) {
            ExportView(store: store) {
                showExport = false
            }
        }
        .sheet(isPresented: $showAudioTriage) {
            AudioTriageView(store: store) {
                showAudioTriage = false
            }
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Text("🏀")
                    .font(.title2)
                Text("HoopTriage")
                    .font(.system(size: 16, weight: .bold))
            }
            
            if !store.clips.isEmpty {
                Divider().frame(height: 20)
                
                HStack(spacing: 14) {
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
            
            // Audio Triage button
            if !store.clips.isEmpty {
                Button(action: { showAudioTriage = true }) {
                    Label("Audio Triage", systemImage: "waveform")
                }
                .help("Analyze audio to suggest ratings for unrated clips")
                
                // Accept All (when suggestions exist)
                if store.suggestedCount > 0 {
                    Button(action: { store.acceptAllSuggestions() }) {
                        Label("Accept All (\(store.suggestedCount))", systemImage: "checkmark.circle")
                    }
                    .help("Accept all audio suggestions as confirmed ratings")
                }
            }
            
            // Export button
            if !store.clips.isEmpty {
                Button(action: { showExport = true }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export triaged clips to folders")
            }
            
            // Undo / Redo buttons
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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
    
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
            // Warm gradient background
            LinearGradient(
                colors: isDragTargeted
                    ? [Color.orange.opacity(0.08), Color.accentColor.opacity(0.06)]
                    : [Color(nsColor: .windowBackgroundColor), Color.orange.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
                                    colors: [Color.orange.opacity(0.15), Color.clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 160, height: 160)
                            .scaleEffect(heroAnimating ? 1.1 : 0.95)
                            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: heroAnimating)
                        
                        // Film strip icons floating around
                        Image(systemName: "film")
                            .font(.system(size: 20))
                            .foregroundColor(.orange.opacity(0.3))
                            .offset(x: -45, y: -30)
                            .rotationEffect(.degrees(heroAnimating ? -8 : 8))
                            .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: heroAnimating)
                        
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow.opacity(0.4))
                            .offset(x: 50, y: -25)
                            .rotationEffect(.degrees(heroAnimating ? 10 : -5))
                            .animation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true), value: heroAnimating)
                        
                        Image(systemName: "tag.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange.opacity(0.3))
                            .offset(x: 45, y: 30)
                            .rotationEffect(.degrees(heroAnimating ? -5 : 10))
                            .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: heroAnimating)
                        
                        // Main icon
                        Image(systemName: "basketball.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .orange.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(isDragTargeted ? 1.15 : 1.0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isDragTargeted)
                    }
                    
                    // Headlines
                    VStack(spacing: 10) {
                        Text("Triage your game footage")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("Rate, tag, and organize clips — all from one place")
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
                                    colors: [.orange, .orange.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: .orange.opacity(0.3), radius: 8, y: 4)
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
                                .foregroundColor(isDragTargeted ? .orange : .secondary.opacity(0.4))
                                .scaleEffect(isDragTargeted ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3), value: isDragTargeted)
                            
                            Text("Drop folders or video files here")
                                .font(.system(size: 13))
                                .foregroundColor(isDragTargeted ? .orange : .secondary.opacity(0.6))
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 40)
                        .frame(maxWidth: 360)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isDragTargeted ? Color.orange : Color.secondary.opacity(0.15),
                                    style: StrokeStyle(lineWidth: isDragTargeted ? 2 : 1.5, dash: [8, 4])
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isDragTargeted ? Color.orange.opacity(0.05) : Color.clear)
                                )
                        )
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.06), radius: 20, y: 8)
                    )
                    .frame(maxWidth: 440)
                }
                
                Spacer()
                
                // Bottom features strip
                HStack(spacing: 40) {
                    featureItem(icon: "hand.draw", title: "Scrub & Preview", desc: "Hover to preview clips instantly")
                    featureItem(icon: "star", title: "Quick Rate", desc: "1-5 keyboard shortcuts")
                    featureItem(icon: "tag", title: "Multi-Tag", desc: "Organize by plays, drills & more")
                    featureItem(icon: "square.and.arrow.up", title: "Export", desc: "Sorted folders by rating")
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
                .foregroundColor(.orange.opacity(0.7))
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
