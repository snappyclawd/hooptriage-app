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
            HStack {
                Text(clip.filename)
                    .font(.headline)
                
                Spacer()
                
                Text(clip.durationFormatted)
                    .foregroundColor(.secondary)
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            // Video player
            if let player = player {
                VideoPlayer(player: player)
                    .frame(maxHeight: 600)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
        .onAppear {
            player = AVPlayer(url: clip.url)
            player?.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
