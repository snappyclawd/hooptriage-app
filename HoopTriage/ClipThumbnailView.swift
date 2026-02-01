import SwiftUI
import AVFoundation

/// A single clip card with hover-scrub, poster, rating, and tags
struct ClipThumbnailView: View {
    let clip: Clip
    let isHovered: Bool
    @Binding var showTagPickerBinding: Bool
    let thumbnailGenerator: ThumbnailGenerator
    let availableTags: [String]
    let audioEnabled: Bool
    let onRate: (Int) -> Void
    let onToggleTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let onAddTag: (String) -> Void
    let onHoverChange: (Bool) -> Void
    let onRemove: () -> Void
    let onOpen: () -> Void
    
    @State private var posterImage: NSImage? = nil
    @State private var scrubImage: NSImage? = nil
    @State private var isHovering = false
    @State private var hoverProgress: CGFloat = 0
    @State private var currentTime: Double = 0
    @State private var hoveredStar: Int = 0
    @State private var showTagPicker = false
    @State private var newTagText = ""
    @State private var audioPlayer: AVPlayer? = nil
    @State private var lastAudioSeek: Double = -1
    @State private var isCardHovered = false  // tracks hover over ENTIRE card
    
    private let scrubSize = CGSize(width: 480, height: 270)
    
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
                    Color.black
                    
                    if let img = isHovering ? (scrubImage ?? posterImage) : posterImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    
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
                    
                    // Delete button (top-right, on card hover)
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
                    
                    // Tag pills overlay (top-left, below rating if present)
                    if !clip.tags.isEmpty {
                        VStack {
                            HStack {
                                if clip.rating > 0 {
                                    Spacer().frame(width: 0) // rating badge is already there
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
                        
                        if !wasHovering && audioEnabled {
                            prepareAudio()
                        }
                        
                        Task {
                            let img = await thumbnailGenerator.thumbnail(
                                for: clip.url,
                                at: currentTime,
                                size: scrubSize
                            )
                            await MainActor.run {
                                if isHovering { scrubImage = img }
                            }
                        }
                        
                        if audioEnabled {
                            let delta = abs(currentTime - lastAudioSeek)
                            if delta > 0.3 {
                                seekAudio(to: currentTime)
                            }
                        }
                        
                    case .ended:
                        isHovering = false
                        scrubImage = nil
                        hoverProgress = 0
                        stopAudio()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    onOpen()
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            
            // Info bar — click to open
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(clip.filename)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(clip.durationFormatted)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 6) {
                    starRating
                    Spacer()
                    tagDisplay
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .contentShape(Rectangle())
            .onTapGesture {
                onOpen()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        // Track hover over the ENTIRE card for hoveredClipID and delete button
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
        .task {
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
        return HStack(spacing: 3) {
            Text("\(clip.rating)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text("★")
                .font(.system(size: 13))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
    
    // MARK: - Audio Scrub
    
    private func prepareAudio() {
        if audioPlayer == nil {
            let playerItem = AVPlayerItem(url: clip.url)
            audioPlayer = AVPlayer(playerItem: playerItem)
            audioPlayer?.volume = 0.5
        }
    }
    
    private func seekAudio(to time: Double) {
        guard let player = audioPlayer else { return }
        lastAudioSeek = time
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            player.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if abs(self.currentTime - time) < 0.5 {
                    player.pause()
                }
            }
        }
    }
    
    private func stopAudio() {
        audioPlayer?.pause()
        audioPlayer = nil
        lastAudioSeek = -1
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
        return star <= clip.rating ? .yellow : Color.gray.opacity(0.25)
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
                    .cornerRadius(10)
            }
            
            Image(systemName: "tag")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .onTapGesture { showTagPicker.toggle() }
        }
        .popover(isPresented: $showTagPicker, arrowEdge: .bottom) {
            tagPickerContent
        }
    }
    
    private var tagPickerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(availableTags, id: \.self) { tag in
                Button(action: {
                    onToggleTag(tag)
                }) {
                    HStack {
                        Image(systemName: clip.tags.contains(tag) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundColor(clip.tags.contains(tag) ? tagColor(for: tag) : .secondary.opacity(0.4))
                        Circle()
                            .fill(tagColor(for: tag))
                            .frame(width: 8, height: 8)
                        Text(tag)
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            
            Divider()
            
            HStack(spacing: 4) {
                TextField("New tag...", text: $newTagText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        let tag = newTagText.trimmingCharacters(in: .whitespaces)
                        if !tag.isEmpty {
                            onAddTag(tag)
                            onToggleTag(tag)
                            newTagText = ""
                        }
                    }
                
                Button(action: {
                    let tag = newTagText.trimmingCharacters(in: .whitespaces)
                    if !tag.isEmpty {
                        onAddTag(tag)
                        onToggleTag(tag)
                        newTagText = ""
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            if !clip.tags.isEmpty {
                Divider()
                Button(action: {
                    for tag in clip.tags {
                        onRemoveTag(tag)
                    }
                    showTagPicker = false
                }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text("Clear all tags")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .padding(6)
        .frame(width: 200)
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
