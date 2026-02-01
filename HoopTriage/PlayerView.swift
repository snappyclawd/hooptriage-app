import SwiftUI
import AVKit

/// Expanded video player for a clip
struct PlayerView: View {
    let clip: Clip
    let onClose: () -> Void
    
    @State private var player: AVPlayer?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.filename)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    // File location
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                        Text(clip.url.deletingLastPathComponent().path)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .foregroundColor(.secondary)
                    
                    // Metadata row
                    HStack(spacing: 16) {
                        metaItem(icon: "clock", value: clip.durationFormatted)
                        
                        if clip.width > 0 && clip.height > 0 {
                            metaItem(icon: "rectangle", value: "\(clip.width)×\(clip.height)")
                        }
                        
                        if clip.fileSizeFormatted != nil {
                            metaItem(icon: "doc", value: clip.fileSizeFormatted!)
                        }
                        
                        if clip.rating > 0 {
                            HStack(spacing: 2) {
                                Text("\(clip.rating)")
                                    .font(.system(size: 12, weight: .bold))
                                Text("★")
                                    .font(.system(size: 11))
                                    .foregroundColor(.yellow)
                            }
                        }
                        
                        if let tag = clip.category {
                            Text(tag)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(tagColor(for: tag))
                                .cornerRadius(8)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }
                
                Spacer()
                
                // Reveal in Finder button
                Button(action: {
                    NSWorkspace.shared.selectFile(clip.url.path, inFileViewerRootedAtPath: clip.url.deletingLastPathComponent().path)
                }) {
                    Image(systemName: "arrow.right.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            // Video player
            if let player = player {
                VideoPlayer(player: player)
                    .frame(minHeight: 400, maxHeight: 600)
                    .cornerRadius(8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 20)
        .onAppear {
            player = AVPlayer(url: clip.url)
            player?.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func metaItem(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(value)
        }
    }
    
    private func tagColor(for tag: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .teal, .indigo, .mint, .cyan]
        let hash = abs(tag.hashValue)
        return colors[hash % colors.count]
    }
}
