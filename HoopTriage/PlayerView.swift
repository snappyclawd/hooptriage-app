import SwiftUI
import AVKit

/// Playback speed levels for JKL scrubbing
private let speedLevels: [Float] = [1, 2, 4, 8]

/// Expanded video player with JKL scrubbing and keyboard controls
struct PlayerView: View {
    let clip: Clip
    let onRate: (Int) -> Void
    let onToggleTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let availableTags: [String]
    let onAddTag: (String) -> Void
    let onClose: () -> Void
    
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playbackDirection: Int = 0  // -1 = reverse, 0 = paused, 1 = forward
    @State private var speedIndex: Int = 0
    @State private var currentTime: Double = 0
    @State private var isScrubbing = false
    @State private var showTagPicker = false
    @State private var newTagText = ""
    @State private var hoveredStar: Int = 0
    @FocusState private var isFocused: Bool
    
    @State private var timeObserver: Any? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar — compact
            headerBar
            
            Divider()
            
            // Video player
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(0)
            }
            
            // Custom scrub bar
            scrubBar
            
            Divider()
            
            // Bottom bar: rating + tag + transport info
            bottomBar
        }
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(radius: 20)
        .focused($isFocused)
        .onKeyPress(.space) { togglePlayPause(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "l")) { _ in handleL(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "j")) { _ in handleJ(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "k")) { _ in handleK(); return .handled }
        .onKeyPress(characters: .init(charactersIn: ",")) { _ in stepFrame(forward: false); return .handled }
        .onKeyPress(characters: .init(charactersIn: ".")) { _ in stepFrame(forward: true); return .handled }
        .onKeyPress(characters: .init(charactersIn: "[")) { _ in jumpTime(by: -5); return .handled }
        .onKeyPress(characters: .init(charactersIn: "]")) { _ in jumpTime(by: 5); return .handled }
        .onKeyPress(characters: .init(charactersIn: "12345")) { press in
            if let digit = Int(String(press.characters)), (1...5).contains(digit) {
                onRate(digit)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: .init(charactersIn: "t")) { _ in
            showTagPicker.toggle()
            return .handled
        }
        .onKeyPress(.escape) {
            if showTagPicker {
                showTagPicker = false
                return .handled
            }
            onClose()
            return .handled
        }
        .onAppear {
            let p = AVPlayer(url: clip.url)
            player = p
            // Start paused
            p.pause()
            isPlaying = false
            playbackDirection = 0
            speedIndex = 0
            isFocused = true
            
            timeObserver = p.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
                queue: .main
            ) { time in
                if !isScrubbing {
                    currentTime = CMTimeGetSeconds(time)
                }
            }
        }
        .onDisappear {
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
            }
            player?.pause()
            player = nil
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.filename)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    metaItem(icon: "clock", value: clip.durationFormatted)
                    if clip.width > 0 && clip.height > 0 {
                        metaItem(icon: "rectangle", value: "\(clip.width)×\(clip.height)")
                    }
                    if let size = clip.fileSizeFormatted {
                        metaItem(icon: "doc", value: size)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Reveal in Finder
            Button(action: {
                NSWorkspace.shared.selectFile(clip.url.path, inFileViewerRootedAtPath: clip.url.deletingLastPathComponent().path)
            }) {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Scrub Bar
    
    private var scrubBar: some View {
        VStack(spacing: 0) {
            // Clickable/draggable timeline
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                    
                    // Progress fill
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: clip.duration > 0 ? geo.size.width * CGFloat(currentTime / clip.duration) : 0)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let progress = max(0, min(1, value.location.x / geo.size.width))
                            let time = Double(progress) * clip.duration
                            currentTime = time
                            player?.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                        .onEnded { _ in
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 6)
            .cornerRadius(3)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            // Time labels + transport status
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Transport status
                if playbackDirection != 0 {
                    HStack(spacing: 3) {
                        Image(systemName: playbackDirection == -1 ? "backward.fill" : "forward.fill")
                            .font(.system(size: 9))
                        Text("\(Int(speedLevels[speedIndex]))×")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.accentColor)
                } else {
                    Text("Paused")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                
                Spacer()
                
                Text(formatTime(clip.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 2)
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Play/Pause button
            Button(action: { togglePlayPause() }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Space")
            
            // Step back / forward
            Button(action: { stepFrame(forward: false) }) {
                Image(systemName: "backward.frame.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help(", key")
            
            Button(action: { stepFrame(forward: true) }) {
                Image(systemName: "forward.frame.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help(". key")
            
            Divider().frame(height: 18)
            
            // Star rating
            playerStarRating
            
            Divider().frame(height: 18)
            
            // Tag
            playerTagButton
            
            Spacer()
            
            // Keyboard hint (subtle)
            Text("J K L  scrub  ·  , .  frame  ·  [ ]  ±5s")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - JKL Scrubbing
    
    /// L key: play forward, accelerate with each press
    private func handleL() {
        guard let player = player else { return }
        
        if playbackDirection == 1 {
            // Already forward — speed up
            speedIndex = min(speedIndex + 1, speedLevels.count - 1)
        } else {
            // Was paused or reverse — start forward at 1x
            playbackDirection = 1
            speedIndex = 0
        }
        
        player.rate = speedLevels[speedIndex]
        isPlaying = true
    }
    
    /// J key: play reverse using native AVPlayer negative rate
    private func handleJ() {
        guard let player = player else { return }
        
        if playbackDirection == -1 {
            // Already reverse — speed up
            speedIndex = min(speedIndex + 1, speedLevels.count - 1)
        } else {
            // Was paused or forward — start reverse at 1x
            playbackDirection = -1
            speedIndex = 0
        }
        
        // AVPlayer supports negative rates natively (hardware-decoded reverse)
        player.rate = -speedLevels[speedIndex]
        isPlaying = true
    }
    
    /// K key: pause, reset speed
    private func handleK() {
        player?.pause()
        playbackDirection = 0
        speedIndex = 0
        isPlaying = false
    }
    
    /// Frame step forward or backward
    private func stepFrame(forward: Bool) {
        guard let player = player else { return }
        player.pause()
        playbackDirection = 0
        isPlaying = false
        
        let frameTime = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        if forward {
            player.seek(to: CMTimeAdd(player.currentTime(), frameTime), toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: CMTimeSubtract(player.currentTime(), frameTime), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
    
    /// Jump forward/backward by seconds
    private func jumpTime(by seconds: Double) {
        guard let player = player else { return }
        let target = CMTimeGetSeconds(player.currentTime()) + seconds
        let clamped = max(0, min(target, clip.duration))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    /// Toggle play/pause with Space
    private func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            handleK()
        } else {
            player.rate = 1.0
            playbackDirection = 1
            speedIndex = 0
            isPlaying = true
        }
    }
    
    // MARK: - Star Rating
    
    private var playerStarRating: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Text("★")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(playerStarColor(for: star))
                    .scaleEffect(hoveredStar == star ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: hoveredStar)
                    .onHover { isOver in
                        hoveredStar = isOver ? star : 0
                    }
                    .onTapGesture {
                        onRate(star)
                    }
            }
        }
    }
    
    private func playerStarColor(for star: Int) -> Color {
        if hoveredStar > 0 {
            return star <= hoveredStar ? .orange : Color.gray.opacity(0.25)
        }
        return star <= clip.rating ? .yellow : Color.gray.opacity(0.25)
    }
    
    // MARK: - Tag Button
    
    private var playerTagButton: some View {
        HStack(spacing: 4) {
            // Show existing tags as pills
            ForEach(Array(clip.tags).sorted(), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tagColor(for: tag))
                    .cornerRadius(8)
            }
            
            // Add/edit tag button
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.system(size: 12))
                if clip.tags.isEmpty {
                    Text("Tag")
                        .font(.system(size: 11))
                }
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            .onTapGesture { showTagPicker.toggle() }
        }
        .popover(isPresented: $showTagPicker, arrowEdge: .top) {
            playerTagPickerContent
        }
    }
    
    private var playerTagPickerContent: some View {
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
    
    private func metaItem(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(value)
        }
    }
    
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
