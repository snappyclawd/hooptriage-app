import SwiftUI
import AVFoundation

/// A single clip card with hover-scrub, poster, rating, and tags.
///
/// Scrubbing uses a shared AVPlayer from ScrubPlayerPool, only acquired
/// on hover-enter and released on hover-leave. The AVPlayerLayer renders
/// decoded frames directly via GPU. Seeks are coalesced to avoid stutter.
struct ClipThumbnailView: View {
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
    let onAcceptSuggestion: () -> Void
    let onDismissSuggestion: () -> Void
    let onOpen: () -> Void
    
    @State private var posterImage: NSImage? = nil
    @State private var isHovering = false
    @State private var hoverProgress: CGFloat = 0
    @State private var currentTime: Double = 0
    @State private var hoveredStar: Int = 0
    @State private var showTagPicker = false
    
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
                    if clip.effectiveRating > 0 {
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
                    
                    // Accept/Dismiss suggestion buttons
                    if clip.hasSuggestion && isCardHovered {
                        VStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Button(action: onAcceptSuggestion) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Accept")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.green.opacity(0.85))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .help("Accept suggestion (A)")
                                
                                Button(action: onDismissSuggestion) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Dismiss")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.red.opacity(0.7))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .help("Dismiss suggestion (X)")
                            }
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .padding(.bottom, 10)
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
                    onOpen()
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            
            // Info bar
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(clip.filename)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
                    
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
                onOpen()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
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
        let effectiveRating = clip.effectiveRating
        let color = Self.scoreColors[effectiveRating] ?? .gray
        let isSuggested = clip.hasSuggestion
        
        return HStack(spacing: 3) {
            if isSuggested {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
            }
            Text("\(effectiveRating)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("★")
                .font(.system(size: 15))
        }
        .foregroundColor(isSuggested ? color : .white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSuggested ? color.opacity(0.2) : color)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSuggested ? color : Color.clear, lineWidth: 1.5, antialiased: true)
        )
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
    
    // MARK: - Star Rating
    
    private var starRating: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { star in
                Text("★")
                    .font(.system(size: 22, weight: .medium))
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
            return star <= hoveredStar ? .orange : Color.gray.opacity(0.25)
        }
        if clip.rating > 0 {
            return star <= clip.rating ? .yellow : Color.gray.opacity(0.25)
        }
        if clip.suggestedRating > 0 {
            return star <= clip.suggestedRating ? Color.blue.opacity(0.5) : Color.gray.opacity(0.25)
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
}
