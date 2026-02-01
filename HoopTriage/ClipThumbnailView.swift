import SwiftUI
import AVFoundation

/// A single clip card with hover-scrub, poster, rating, and tags
struct ClipThumbnailView: View {
    let clip: Clip
    let thumbnailGenerator: ThumbnailGenerator
    let availableTags: [String]
    let audioEnabled: Bool
    let onRate: (Int) -> Void
    let onTag: (String?) -> Void
    let onAddTag: (String) -> Void
    let onDoubleClick: () -> Void
    
    @State private var posterImage: NSImage? = nil
    @State private var scrubImage: NSImage? = nil
    @State private var isHovering = false
    @State private var hoverProgress: CGFloat = 0
    @State private var currentTime: Double = 0
    @State private var hoveredStar: Int = 0
    @State private var showTagPicker = false
    @State private var newTagText = ""
    @State private var audioPlayer: AVPlayer? = nil
    
    private let scrubSize = CGSize(width: 480, height: 270)
    
    var body: some View {
        VStack(spacing: 0) {
            // Video area
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
                        isHovering = true
                        let progress = max(0, min(1, location.x / geo.size.width))
                        hoverProgress = progress
                        currentTime = clip.duration * Double(progress)
                        
                        // Generate thumbnail
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
                        
                        // Audio scrub
                        if audioEnabled {
                            scrubAudio(to: currentTime)
                        }
                        
                    case .ended:
                        isHovering = false
                        scrubImage = nil
                        hoverProgress = 0
                        stopAudio()
                    }
                }
                .onTapGesture(count: 2) {
                    onDoubleClick()
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            
            // Info bar
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(clip.filename)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(clip.durationFormatted)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 6) {
                    starRating
                    Spacer()
                    tagButton
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        .task {
            posterImage = await thumbnailGenerator.poster(
                for: clip.url,
                duration: clip.duration,
                size: scrubSize
            )
        }
    }
    
    // MARK: - Audio Scrub
    
    private func scrubAudio(to time: Double) {
        if audioPlayer == nil {
            let playerItem = AVPlayerItem(url: clip.url)
            audioPlayer = AVPlayer(playerItem: playerItem)
            audioPlayer?.volume = 0.5
        }
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        audioPlayer?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600))
        audioPlayer?.play()
    }
    
    private func stopAudio() {
        audioPlayer?.pause()
        audioPlayer = nil
    }
    
    // MARK: - Star Rating
    
    private var starRating: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Text("★")
                    .font(.system(size: 18, weight: .medium))
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
    
    // MARK: - Tag Picker
    
    private var tagButton: some View {
        Group {
            if let tag = clip.category {
                Text(tag)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tagColor(for: tag))
                    .cornerRadius(10)
                    .onTapGesture { showTagPicker.toggle() }
            } else {
                Image(systemName: "tag")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .onTapGesture { showTagPicker.toggle() }
            }
        }
        .popover(isPresented: $showTagPicker, arrowEdge: .bottom) {
            tagPickerContent
        }
    }
    
    private var tagPickerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(availableTags, id: \.self) { tag in
                Button(action: {
                    if clip.category == tag {
                        onTag(nil)
                    } else {
                        onTag(tag)
                    }
                    showTagPicker = false
                }) {
                    HStack {
                        Circle()
                            .fill(tagColor(for: tag))
                            .frame(width: 8, height: 8)
                        Text(tag)
                            .font(.system(size: 12))
                        Spacer()
                        if clip.category == tag {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .cornerRadius(4)
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
                            onTag(tag)
                            newTagText = ""
                            showTagPicker = false
                        }
                    }
                
                Button(action: {
                    let tag = newTagText.trimmingCharacters(in: .whitespaces)
                    if !tag.isEmpty {
                        onAddTag(tag)
                        onTag(tag)
                        newTagText = ""
                        showTagPicker = false
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
            
            if clip.category != nil {
                Divider()
                Button(action: {
                    onTag(nil)
                    showTagPicker = false
                }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text("Remove tag")
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
        .frame(width: 180)
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
