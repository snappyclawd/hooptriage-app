import SwiftUI
import AVFoundation
import AppKit

// MARK: - Auto-Focus + Select-All TextField

/// An NSTextField wrapper that immediately focuses and selects all text on appear.
struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 13, weight: .semibold)
    var onCommit: () -> Void
    var onCancel: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.font = font
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .exterior
        field.delegate = context.coordinator
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        
        // Focus and select all on next run loop so the field is in the window
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        
        return field
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only push text changes outward (coordinator handles inward)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: RenameTextField
        
        init(_ parent: RenameTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

/// A single clip card with hover-scrub, poster, rating, and tags.
///
/// Scrubbing uses a shared AVPlayer from ScrubPlayerPool, only acquired
/// on hover-enter and released on hover-leave. The AVPlayerLayer renders
/// decoded frames directly via GPU. Seeks are coalesced to avoid stutter.
struct ClipThumbnailView: View {
    @EnvironmentObject var settings: AppSettings
    let clip: Clip
    let isHovered: Bool
    @Binding var showTagPickerBinding: Bool
    let thumbnailGenerator: ThumbnailGenerator
    let scrubPlayerPool: ScrubPlayerPool
    let audioScrubEngine: AudioScrubEngine
    let availableTags: [String]
    let audioEnabled: Bool
    let onRate: (Int) -> Void
    let onToggleTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let onAddTag: (String) -> Void
    let onHoverChange: (Bool) -> Void
    let onRemove: () -> Void
    let onOpen: () -> Void
    let onRename: (String) -> Void
    let onRenameStateChanged: (Bool) -> Void
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let isSelected: Bool
    
    @State private var posterImage: NSImage? = nil
    @State private var isHovering = false
    @State private var hoverProgress: CGFloat = 0
    @State private var currentTime: Double = 0
    @State private var hoveredStar: Int = 0
    @State private var showTagPicker = false
    @State private var isRenaming = false
    @State private var renameText = ""
    
    @State private var isCardHovered = false
    // AVPlayer-based scrub — only created on hover-enter
    @State private var scrubPlayer: AVPlayer? = nil
    
    private let scrubSize = CGSize(width: 480, height: 270)
    private let cardRadius: CGFloat = 14
    
    private static let scoreColors: [Int: Color] = [
        5: Color(red: 0.133, green: 0.773, blue: 0.369),
        4: Color(red: 0.518, green: 0.800, blue: 0.086),
        3: Color(red: 0.918, green: 0.702, blue: 0.031),
        2: Color(red: 0.976, green: 0.451, blue: 0.086),
        1: Color(red: 0.937, green: 0.267, blue: 0.267),
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Video area — hover to scrub
            GeometryReader { geo in
                ZStack {
                    // Unified NSView: poster CALayer on top of AVPlayerLayer.
                    // Poster hides via KVO when AVPlayerLayer.isReadyForDisplay fires.
                    // Sync cache fallback eliminates black flash on fast scroll when
                    // LazyVGrid destroys/recreates views and @State posterImage resets.
                    ScrubPlayerView(
                        player: scrubPlayer,
                        posterImage: posterImage ?? thumbnailGenerator.cachedPosterSync(
                            for: clip.url, duration: clip.duration, size: scrubSize
                        )
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    
                    // Rating badge (top-left)
                    if clip.rating > 0 {
                        VStack {
                            HStack {
                                ratingBadge.padding(6)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                    
                    // Action buttons (top-right, on card hover)
                    if isCardHovered {
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: onOpen) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                        .frame(width: 26, height: 26)
                                        .background(.black.opacity(0.4))
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.5), radius: 2)
                                }
                                .buttonStyle(.plain)
                                .help("Expand (Enter)")
                                Button(action: onRemove) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white.opacity(0.8))
                                        .shadow(color: .black.opacity(0.5), radius: 2)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from triage (Del)")
                                .padding(6)
                            }
                            Spacer()
                        }
                    }
                    
                    // Tag pills overlay
                    if !clip.tags.isEmpty {
                        VStack {
                            HStack {
                                if clip.rating > 0 {
                                    Spacer().frame(width: 0)
                                }
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                    
                    // Time indicator (on hover)
                    if isHovering {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(formatTime(currentTime))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.black.opacity(0.7))
                                    .cornerRadius(4)
                                    .padding(6)
                            }
                        }
                    }
                    
                    // Scrub progress bar
                    if isHovering {
                        VStack {
                            Spacer()
                            GeometryReader { barGeo in
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: barGeo.size.width * hoverProgress, height: 3)
                            }
                            .frame(height: 3)
                        }
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let wasHovering = isHovering
                        isHovering = true
                        let progress = max(0, min(1, location.x / geo.size.width))
                        hoverProgress = progress
                        currentTime = clip.duration * Double(progress)
                        
                        // On hover enter: get a player from the pool
                        if !wasHovering {
                            scrubPlayer = scrubPlayerPool.player(for: clip.url)
                            // First seek — poster hides via KVO when AVPlayerLayer
                            // reports isReadyForDisplay (handled in ScrubPlayerNSView)
                            if let player = scrubPlayer {
                                scrubPlayerPool.seek(player, to: currentTime)
                            }
                            if audioEnabled { audioScrubEngine.prepareAudio(for: clip.url) }
                        } else {
                            // Subsequent moves: coalesced seek
                            if let player = scrubPlayer {
                                scrubPlayerPool.seek(player, to: currentTime)
                            }
                        }
                        
                        if audioEnabled {
                            audioScrubEngine.scrub(url: clip.url, to: currentTime)
                        }
                        
                    case .ended:
                        isHovering = false
                        scrubPlayer = nil
                        hoverProgress = 0
                        audioScrubEngine.stop()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    let flags = NSEvent.modifierFlags
                    onSelect(flags)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            
            // Info bar
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    if isRenaming {
                        RenameTextField(
                            text: $renameText,
                            font: .systemFont(ofSize: 13, weight: .semibold),
                            onCommit: { commitRename() },
                            onCancel: { cancelRename() }
                        )
                        .frame(height: 22)
                    } else {
                        Text(clip.filename)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.primary)
                            .onTapGesture(count: 2) { startRename() }
                    }
                    
                    Spacer()
                    
                    Text(clip.durationFormatted)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 6) {
                    starRating
                    Spacer()
                    tagDisplay
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .contentShape(Rectangle())
            .onTapGesture {
                let flags = NSEvent.modifierFlags
                onSelect(flags)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius + 4, style: .continuous)
                .inset(by: -4)
                .strokeBorder(isSelected ? settings.accent : Color.clear, lineWidth: 2)
        )
        .shadow(color: isSelected ? settings.accent.opacity(0.25) : .black.opacity(0.08), radius: isSelected ? 12 : 8, y: 3)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onHover { hovering in
            isCardHovered = hovering
            onHoverChange(hovering)
        }
        .onChange(of: showTagPickerBinding) { _, show in
            if show { showTagPicker = true }
        }
        .onChange(of: showTagPicker) { _, show in
            if !show { showTagPickerBinding = false }
        }
        .task(id: clip.id) {
            // Skip if we already have a poster (e.g. view was recreated by LazyVGrid
            // but the @State was preserved or re-initialized quickly)
            guard posterImage == nil else { return }
            posterImage = await thumbnailGenerator.poster(
                for: clip.url,
                duration: clip.duration,
                size: scrubSize
            )
        }
    }
    
    // MARK: - Rating Badge
    
    private var ratingBadge: some View {
        let color = Self.scoreColors[clip.rating] ?? .gray
        
        return HStack(spacing: 2) {
            Text("\(clip.rating)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text("★")
                .font(.system(size: 10))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color)
        .cornerRadius(7)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
    
    // MARK: - Star Rating
    
    private var starRating: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Text("★")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(starColor(for: star))
                    .scaleEffect(hoveredStar == star ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: hoveredStar)
                    .onHover { isOver in
                        hoveredStar = isOver ? star : 0
                    }
                    .onTapGesture {
                        onRate(star)
                    }
            }
        }
        .padding(.vertical, 2)
    }
    
    private func starColor(for star: Int) -> Color {
        if hoveredStar > 0 {
            return star <= hoveredStar ? settings.accent : Color.gray.opacity(0.25)
        }
        if clip.rating > 0 {
            return star <= clip.rating ? .yellow : Color.gray.opacity(0.25)
        }
        return Color.gray.opacity(0.25)
    }
    
    // MARK: - Tag Display & Picker
    
    private var tagDisplay: some View {
        HStack(spacing: 5) {
            ForEach(Array(clip.tags).sorted(), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tagColor(for: tag))
                    .clipShape(Capsule())
            }
            
            Image(systemName: "tag")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .onTapGesture { showTagPicker.toggle() }
        }
        .popover(isPresented: $showTagPicker, arrowEdge: .bottom) {
            TagPickerView(
                availableTags: availableTags,
                selectedTags: clip.tags,
                onToggleTag: onToggleTag,
                onAddTag: onAddTag,
                onDismiss: { showTagPicker = false }
            )
        }
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ time: Double) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func tagColor(for tag: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .teal, .indigo, .mint, .cyan]
        let hash = abs(tag.hashValue)
        return colors[hash % colors.count]
    }
    
    // MARK: - Inline Rename
    
    private func startRename() {
        // Pre-fill with the filename stem (without extension)
        let name = clip.filename
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty {
            renameText = String(name.dropLast(ext.count + 1))
        } else {
            renameText = name
        }
        isRenaming = true
        onRenameStateChanged(true)
    }
    
    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isRenaming = false
        onRenameStateChanged(false)
    }
    
    private func cancelRename() {
        isRenaming = false
        onRenameStateChanged(false)
    }
}
