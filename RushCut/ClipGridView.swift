import SwiftUI

/// Grouping mode
enum GroupMode: String, CaseIterable {
    case none = "No Grouping"
    case rating = "By Rating"
    case category = "By Tag"
}

/// The main grid of clip thumbnails
struct ClipGridView: View {
    @ObservedObject var store: ClipStore
    let audioEnabled: Bool
    @State private var expandedClip: Clip? = nil
    @FocusState private var isGridFocused: Bool
    
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: store.gridColumns)
    }
    
    var body: some View {
        ZStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    // Invisible anchor at top
                    Color.clear.frame(height: 0).id("scrollTop")
                    
                    if store.groupMode == .none {
                        flatGrid
                    } else {
                        groupedGrid
                    }
                }
                .gesture(
                    MagnifyGesture()
                        .onEnded { value in
                            if value.magnification > 1.2 {
                                store.gridColumns = max(1, store.gridColumns - 1)
                            } else if value.magnification < 0.8 {
                                store.gridColumns = min(5, store.gridColumns + 1)
                            }
                        }
                )
                .focusable()
                .focused($isGridFocused)
                .focusEffectDisabled()
                .onChange(of: store.groupMode) { _, _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo("scrollTop", anchor: .top)
                    }
                }
                .onChange(of: store.filterRating) { _, _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo("scrollTop", anchor: .top)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    BackToTopButton {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("scrollTop", anchor: .top)
                        }
                    }
                    .padding(16)
                }
            }
            
            // Expanded player overlay
            if let clip = expandedClip {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { expandedClip = nil }
                
                PlayerView(
                    clip: clip,
                    onRate: { rating in store.setRating(rating, for: clip.id) },
                    onToggleTag: { tag in store.toggleTag(tag, for: clip.id) },
                    onRemoveTag: { tag in store.removeTag(tag, for: clip.id) },
                    availableTags: store.availableTags,
                    onAddTag: { tag in store.addTag(tag) }
                ) {
                    expandedClip = nil
                    isGridFocused = true
                }
                .frame(maxWidth: 1000, maxHeight: 720)
                .padding(48)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: expandedClip?.id)
        .animation(.easeInOut(duration: 0.15), value: store.gridColumns)
        .onKeyPress(.escape) {
            if expandedClip != nil {
                expandedClip = nil
                isGridFocused = true
                return .handled
            }
            return .ignored
        }
        // 1-5 rates the hovered clip
        .onKeyPress(characters: .init(charactersIn: "12345")) { press in
            guard expandedClip == nil else { return .ignored }
            if let digit = Int(String(press.characters)), (1...5).contains(digit),
               let id = store.hoveredClipID {
                store.setRating(digit, for: id)
                return .handled
            }
            return .ignored
        }
        // T opens tag picker on hovered clip
        .onKeyPress(characters: .init(charactersIn: "t")) { press in
            guard expandedClip == nil else { return .ignored }
            if let id = store.hoveredClipID {
                store.showTagPickerForClipID = id
                return .handled
            }
            return .ignored
        }
        // A accepts suggestion on hovered clip
        .onKeyPress(characters: .init(charactersIn: "a")) { _ in
            guard expandedClip == nil else { return .ignored }
            if let id = store.hoveredClipID {
                store.acceptSuggestion(for: id)
                return .handled
            }
            return .ignored
        }
        // X dismisses suggestion on hovered clip
        .onKeyPress(characters: .init(charactersIn: "x")) { _ in
            guard expandedClip == nil else { return .ignored }
            if let id = store.hoveredClipID {
                store.dismissSuggestion(for: id)
                return .handled
            }
            return .ignored
        }
        // Delete removes hovered clip
        .onKeyPress(.delete) {
            guard expandedClip == nil else { return .ignored }
            if let id = store.hoveredClipID {
                store.removeClip(id: id)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.deleteForward) {
            guard expandedClip == nil else { return .ignored }
            if let id = store.hoveredClipID {
                store.removeClip(id: id)
                return .handled
            }
            return .ignored
        }
        // Enter opens hovered clip
        .onKeyPress(.return) {
            guard expandedClip == nil else { return .ignored }
            if let id = store.hoveredClipID,
               let clip = store.sortedAndFilteredClips.first(where: { $0.id == id }) {
                expandedClip = clip
                return .handled
            }
            return .ignored
        }
        .onAppear {
            isGridFocused = true
        }
    }
    
    // MARK: - Flat Grid
    
    private var flatGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(store.sortedAndFilteredClips) { clip in
                clipCard(clip)
            }
        }
        .padding(20)
    }
    
    // MARK: - Grouped Grid
    
    private var groupedGrid: some View {
        LazyVStack(alignment: .leading, spacing: 40) {
            ForEach(groupedSections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        if store.groupMode == .rating {
                            ratingHeader(section.title)
                        } else {
                            Text(section.title)
                                .font(.system(size: 17, weight: .bold))
                        }
                        
                        Text("\(section.clips.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(20)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(section.clips) { clip in
                            clipCard(clip)
                        }
                    }
                }
            }
        }
        .padding(20)
    }
    
    private func ratingHeader(_ title: String) -> some View {
        let scoreColors: [String: Color] = [
            "★★★★★": Color(red: 0.133, green: 0.773, blue: 0.369),
            "★★★★☆": Color(red: 0.518, green: 0.800, blue: 0.086),
            "★★★☆☆": Color(red: 0.918, green: 0.702, blue: 0.031),
            "★★☆☆☆": Color(red: 0.976, green: 0.451, blue: 0.086),
            "★☆☆☆☆": Color(red: 0.937, green: 0.267, blue: 0.267),
        ]
        let color = scoreColors[title] ?? .secondary
        
        return Text(title)
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(color)
    }
    
    // MARK: - Grouped Sections
    
    private struct ClipSection: Identifiable {
        let title: String
        let clips: [Clip]
        var id: String { title }
    }
    
    private var groupedSections: [ClipSection] {
        let clips = store.sortedAndFilteredClips
        
        switch store.groupMode {
        case .none:
            return [ClipSection(title: "All", clips: clips)]
            
        case .rating:
            var groups: [Int: [Clip]] = [:]
            for clip in clips {
                groups[clip.effectiveRating, default: []].append(clip)
            }
            return (0...5).reversed().compactMap { rating in
                guard let clipsInGroup = groups[rating], !clipsInGroup.isEmpty else { return nil }
                let title = rating == 0 ? "Unrated" : String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
                return ClipSection(title: title, clips: clipsInGroup)
            }
            
        case .category:
            // A clip with multiple tags appears in each tag group
            var groups: [String: [Clip]] = [:]
            for clip in clips {
                if clip.tags.isEmpty {
                    groups["Untagged", default: []].append(clip)
                } else {
                    for tag in clip.tags {
                        groups[tag, default: []].append(clip)
                    }
                }
            }
            let sorted = groups.sorted { a, b in
                if a.key == "Untagged" { return false }
                if b.key == "Untagged" { return true }
                return a.key < b.key
            }
            return sorted.map { ClipSection(title: $0.key, clips: $0.value) }
        }
    }
    
    // MARK: - Clip Card
    
    private func clipCard(_ clip: Clip) -> some View {
        ClipThumbnailView(
            clip: clip,
            isHovered: store.hoveredClipID == clip.id,
            showTagPickerBinding: Binding(
                get: { store.showTagPickerForClipID == clip.id },
                set: { if !$0 { store.showTagPickerForClipID = nil } }
            ),
            thumbnailGenerator: store.thumbnailGenerator,
            scrubPlayerPool: store.scrubPlayerPool,
            audioScrubEngine: store.audioScrubEngine,
            availableTags: store.availableTags,
            audioEnabled: audioEnabled,
            onRate: { rating in
                store.setRating(rating, for: clip.id)
            },
            onToggleTag: { tag in
                store.toggleTag(tag, for: clip.id)
            },
            onRemoveTag: { tag in
                store.removeTag(tag, for: clip.id)
            },
            onAddTag: { tag in
                store.addTag(tag)
            },
            onHoverChange: { hovering in
                store.hoveredClipID = hovering ? clip.id : nil
            },
            onRemove: {
                store.removeClip(id: clip.id)
            },
            onAcceptSuggestion: {
                store.acceptSuggestion(for: clip.id)
            },
            onDismissSuggestion: {
                store.dismissSuggestion(for: clip.id)
            },
            onOpen: {
                expandedClip = clip
            }
        )
        .id(clip.id)
    }
}

// MARK: - Back to Top Button

private struct BackToTopButton: View {
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                Text("Top")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isHovered ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .help("Back to top")
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
