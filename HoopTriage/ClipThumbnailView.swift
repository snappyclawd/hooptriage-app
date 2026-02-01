import SwiftUI
import AVFoundation

/// A single clip card with hover-scrub, poster, rating
struct ClipThumbnailView: View {
    let clip: Clip
    let thumbnailGenerator: ThumbnailGenerator
    let onRate: (Int) -> Void
    let onDoubleClick: () -> Void
    
    @State private var posterImage: NSImage? = nil
    @State private var scrubImage: NSImage? = nil
    @State private var isHovering = false
    @State private var hoverProgress: CGFloat = 0
    @State private var currentTime: Double = 0
    
    private let scrubSize = CGSize(width: 480, height: 270)
    
    var body: some View {
        VStack(spacing: 0) {
            // Video area
            GeometryReader { geo in
                ZStack {
                    // Background
                    Color.black
                    
                    // Poster or scrub image
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
                        
                        // Request thumbnail at this time
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
                        
                    case .ended:
                        isHovering = false
                        scrubImage = nil
                        hoverProgress = 0
                    }
                }
                .onTapGesture(count: 2) {
                    onDoubleClick()
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            
            // Info bar
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
                
                // Star rating
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { star in
                        Text("★")
                            .font(.system(size: 14))
                            .foregroundColor(star <= clip.rating ? .yellow : Color.gray.opacity(0.3))
                            .onTapGesture {
                                onRate(star)
                            }
                    }
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
            // Load poster on appear
            posterImage = await thumbnailGenerator.poster(
                for: clip.url,
                duration: clip.duration,
                size: scrubSize
            )
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
