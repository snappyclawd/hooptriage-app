import AVFoundation

/// Provides frame-accurate audio scrubbing by pre-loading audio tracks into
/// PCM buffers and playing short snippets via AVAudioEngine.
///
/// Architecture mirrors ScrubPlayerPool: a single shared instance is owned
/// by ClipStore and passed down to views. Only one clip scrubs at a time.
///
/// How it works:
/// 1. `prepareAudio(for:)` decodes the full audio track into an in-memory
///    AVAudioPCMBuffer using AVAssetReader (runs async, ~10 MB per 30s clip).
/// 2. `scrub(to:)` extracts a short snippet (~80 ms) from the buffer at the
///    requested time and schedules it on AVAudioPlayerNode. A short fade
///    envelope is applied to avoid clicks at buffer boundaries.
/// 3. Snippets are throttled so the engine isn't overwhelmed.
/// 4. `stop()` silences output and releases the active clip.
@MainActor
final class AudioScrubEngine {
    
    // MARK: - Configuration
    
    /// Duration of each audio snippet in seconds.
    private let snippetDuration: Double = 0.08
    
    /// Minimum interval between snippet schedules (seconds).
    private let minSnippetInterval: Double = 0.06
    
    /// Fade duration at snippet edges to avoid clicks (seconds).
    private let fadeDuration: Double = 0.005
    
    /// LRU cache size for pre-loaded audio buffers.
    private let maxCacheSize = 12
    
    // MARK: - Audio Engine
    
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    /// Standard format used for all snippet playback.
    private let playbackFormat: AVAudioFormat
    
    // MARK: - Buffer Cache (LRU)
    
    private var bufferCache: [URL: AVAudioPCMBuffer] = [:]
    private var cacheOrder: [URL] = []
    
    // MARK: - State
    
    /// The URL currently being scrubbed (only one at a time).
    private var activeURL: URL?
    
    /// Timestamp of the last scheduled snippet, for throttling.
    private var lastSnippetTime: CFAbsoluteTime = 0
    
    /// Track loading tasks so we can avoid duplicate loads.
    private var loadingTasks: [URL: Task<Void, Never>] = [:]
    
    // MARK: - Init
    
    init() {
        // 44.1 kHz stereo float — standard for audio processing.
        // If source has different sample rate, AVAssetReader handles conversion.
        playbackFormat = AVAudioFormat(
            standardFormatWithSampleRate: 44_100,
            channels: 2
        )!
        
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
        
        do {
            try engine.start()
        } catch {
            print("[AudioScrubEngine] Failed to start engine: \(error)")
        }
    }
    
    // MARK: - Public API
    
    /// Pre-load the audio track for a clip URL into memory.
    /// Safe to call multiple times — cached results are reused.
    func prepareAudio(for url: URL) {
        // Already cached
        if bufferCache[url] != nil { return }
        // Already loading
        if loadingTasks[url] != nil { return }
        
        loadingTasks[url] = Task {
            if let buffer = await Self.loadAudioBuffer(from: url, format: playbackFormat) {
                self.insertCache(url: url, buffer: buffer)
            }
            self.loadingTasks.removeValue(forKey: url)
        }
    }
    
    /// Play a short audio snippet at the given time for the given clip.
    /// Call this on every scrub position change.
    func scrub(url: URL, to time: Double) {
        // Throttle: skip if too soon after last snippet
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSnippetTime >= minSnippetInterval else { return }
        
        guard let sourceBuffer = bufferCache[url] else {
            // Not loaded yet — trigger load, skip this frame
            prepareAudio(for: url)
            return
        }
        
        activeURL = url
        
        // Ensure engine is running
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        
        // Stop any currently-playing snippet
        playerNode.stop()
        
        let sampleRate = sourceBuffer.format.sampleRate
        let totalFrames = Int(sourceBuffer.frameLength)
        let snippetFrames = Int(snippetDuration * sampleRate)
        let startSample = max(0, min(Int(time * sampleRate), totalFrames - snippetFrames))
        let actualLength = min(snippetFrames, totalFrames - startSample)
        
        guard actualLength > 0 else { return }
        
        // Create snippet buffer
        guard let snippet = AVAudioPCMBuffer(
            pcmFormat: sourceBuffer.format,
            frameCapacity: AVAudioFrameCount(actualLength)
        ) else { return }
        snippet.frameLength = AVAudioFrameCount(actualLength)
        
        // Copy samples from source buffer
        let channelCount = Int(sourceBuffer.format.channelCount)
        guard let srcData = sourceBuffer.floatChannelData,
              let dstData = snippet.floatChannelData else { return }
        
        for ch in 0..<channelCount {
            let src = srcData[ch].advanced(by: startSample)
            dstData[ch].update(from: src, count: actualLength)
        }
        
        // Apply fade envelope to avoid clicks
        applyFadeEnvelope(to: snippet)
        
        // If snippet format doesn't match playback format, we need a converter.
        // In practice, loadAudioBuffer outputs in playbackFormat, so this is a
        // safety net.
        if snippet.format == playbackFormat {
            playerNode.scheduleBuffer(snippet, at: nil, options: [])
        } else if let converted = convert(snippet, to: playbackFormat) {
            playerNode.scheduleBuffer(converted, at: nil, options: [])
        } else {
            return
        }
        
        playerNode.play()
        lastSnippetTime = now
    }
    
    /// Stop audio scrubbing.
    func stop() {
        playerNode.stop()
        activeURL = nil
    }
    
    /// Set the scrub audio volume (0.0–1.0).
    func setVolume(_ volume: Float) {
        playerNode.volume = volume
    }
    
    // MARK: - Audio Loading (off main actor)
    
    /// Decode the full audio track from a URL into a PCM buffer.
    private static func loadAudioBuffer(
        from url: URL,
        format: AVAudioFormat
    ) async -> AVAudioPCMBuffer? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVURLAsset(url: url)
                
                guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Configure reader with output in our standard format
                let outputSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsNonInterleaved: true, // matches AVAudioPCMBuffer layout
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                ]
                
                guard let reader = try? AVAssetReader(asset: asset) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let output = AVAssetReaderTrackOutput(
                    track: audioTrack,
                    outputSettings: outputSettings
                )
                output.alwaysCopiesSampleData = false
                
                guard reader.canAdd(output) else {
                    continuation.resume(returning: nil)
                    return
                }
                reader.add(output)
                
                guard reader.startReading() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Read all sample buffers and accumulate frames
                var allSamples: [[Float]] = Array(
                    repeating: [],
                    count: Int(format.channelCount)
                )
                
                while let sampleBuffer = output.copyNextSampleBuffer() {
                    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                        continue
                    }
                    
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
                    let channelCount = Int(format.channelCount)
                    
                    // For non-interleaved float32, each channel's samples are
                    // laid out sequentially in the block buffer:
                    // [ch0_sample0, ch0_sample1, ...], [ch1_sample0, ...]
                    var dataPointer: UnsafeMutablePointer<Int8>?
                    CMBlockBufferGetDataPointer(
                        blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                        totalLengthOut: nil, dataPointerOut: &dataPointer
                    )
                    
                    guard let rawPtr = dataPointer else { continue }
                    
                    // Non-interleaved: each channel block is frameCount floats
                    let floatPtr = rawPtr.withMemoryRebound(
                        to: Float.self, capacity: length / 4
                    ) { $0 }
                    
                    for ch in 0..<channelCount {
                        let offset = ch * frameCount
                        let channelSamples = Array(
                            UnsafeBufferPointer(
                                start: floatPtr.advanced(by: offset),
                                count: frameCount
                            )
                        )
                        allSamples[ch].append(contentsOf: channelSamples)
                    }
                }
                
                guard reader.status == .completed else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let totalFrames = allSamples[0].count
                guard totalFrames > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Build the final AVAudioPCMBuffer
                guard let pcmBuffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: AVAudioFrameCount(totalFrames)
                ) else {
                    continuation.resume(returning: nil)
                    return
                }
                pcmBuffer.frameLength = AVAudioFrameCount(totalFrames)
                
                guard let channelData = pcmBuffer.floatChannelData else {
                    continuation.resume(returning: nil)
                    return
                }
                
                for ch in 0..<Int(format.channelCount) {
                    allSamples[ch].withUnsafeBufferPointer { src in
                        channelData[ch].update(from: src.baseAddress!, count: totalFrames)
                    }
                }
                
                continuation.resume(returning: pcmBuffer)
            }
        }
    }
    
    // MARK: - Fade Envelope
    
    /// Apply a short linear fade-in and fade-out to avoid clicks.
    private func applyFadeEnvelope(to buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate
        let fadeSamples = min(Int(fadeDuration * sampleRate), frameCount / 2)
        
        guard fadeSamples > 0, let channelData = buffer.floatChannelData else { return }
        
        for ch in 0..<channelCount {
            let data = channelData[ch]
            
            // Fade in
            for i in 0..<fadeSamples {
                let gain = Float(i) / Float(fadeSamples)
                data[i] *= gain
            }
            
            // Fade out
            for i in 0..<fadeSamples {
                let gain = Float(i) / Float(fadeSamples)
                data[frameCount - 1 - i] *= gain
            }
        }
    }
    
    // MARK: - Format Conversion
    
    /// Convert a buffer to a different format (safety net).
    private func convert(
        _ buffer: AVAudioPCMBuffer,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            return nil
        }
        
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )
        guard let output = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity
        ) else { return nil }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: output, error: &error, withInputFrom: inputBlock)
        return error == nil ? output : nil
    }
    
    // MARK: - LRU Cache
    
    private func insertCache(url: URL, buffer: AVAudioPCMBuffer) {
        bufferCache[url] = buffer
        cacheOrder.removeAll { $0 == url }
        cacheOrder.append(url)
        
        // Evict oldest if over capacity
        while cacheOrder.count > maxCacheSize {
            let evicted = cacheOrder.removeFirst()
            bufferCache.removeValue(forKey: evicted)
        }
    }
}
