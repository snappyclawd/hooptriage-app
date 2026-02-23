import Foundation
import AVFoundation

/// Analyzes audio tracks of video clips to score "excitement" level
/// Based on: loudness (RMS), peak transients, and dynamic range
struct AudioAnalyzer {
    
    /// Analyze a single clip's audio and return an excitement score (0.0 - 1.0)
    static func analyzeExcitement(url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            return 0 // No audio track
        }
        
        // Read audio samples
        guard let reader = try? AVAssetReader(asset: asset) else { return 0 }
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16000,       // Downsample to 16kHz for speed
            AVNumberOfChannelsKey: 1,      // Mono
        ]
        
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        
        guard reader.startReading() else { return 0 }
        
        var allSamples: [Float] = []
        
        while let buffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            _ = data.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
            }
            
            // Convert Int16 samples to Float
            let sampleCount = length / 2
            data.withUnsafeBytes { rawPtr in
                let int16Ptr = rawPtr.bindMemory(to: Int16.self)
                for i in 0..<sampleCount {
                    allSamples.append(Float(int16Ptr[i]) / 32768.0)
                }
            }
        }
        
        guard allSamples.count > 0 else { return 0 }
        
        // Calculate metrics in windows (100ms windows at 16kHz = 1600 samples)
        let windowSize = 1600
        let windowCount = allSamples.count / windowSize
        guard windowCount > 0 else { return 0 }
        
        var windowRMS: [Float] = []
        var windowPeaks: [Float] = []
        
        for i in 0..<windowCount {
            let start = i * windowSize
            let end = min(start + windowSize, allSamples.count)
            let window = allSamples[start..<end]
            
            // RMS (loudness)
            let sumSquares = window.reduce(0.0) { $0 + $1 * $1 }
            let rms = sqrt(sumSquares / Float(window.count))
            windowRMS.append(rms)
            
            // Peak
            let peak = window.map { abs($0) }.max() ?? 0
            windowPeaks.append(peak)
        }
        
        // Overall metrics
        let avgRMS = windowRMS.reduce(0, +) / Float(windowRMS.count)
        let maxRMS = windowRMS.max() ?? 0
        
        // Dynamic range: how much variation between quiet and loud parts
        let sortedRMS = windowRMS.sorted()
        let p10 = sortedRMS[Int(Float(sortedRMS.count) * 0.1)]
        let p90 = sortedRMS[Int(Float(sortedRMS.count) * 0.9)]
        let dynamicRange = p90 - p10
        
        // Spike count: windows that are significantly louder than average
        let spikeThreshold = avgRMS * 2.0
        let spikeCount = windowRMS.filter { $0 > spikeThreshold }.count
        let spikeRatio = Float(spikeCount) / Float(windowCount)
        
        // Combine into excitement score (0-1)
        // Weight: loudness matters most, then spikes, then dynamic range
        let loudnessScore = min(1.0, Double(maxRMS) / 0.3)          // normalize: 0.3 RMS = very loud
        let spikeScore = min(1.0, Double(spikeRatio) / 0.15)        // normalize: 15% spike windows = exciting
        let dynamicScore = min(1.0, Double(dynamicRange) / 0.15)     // normalize: 0.15 range = good variation
        
        let excitement = loudnessScore * 0.5 + spikeScore * 0.3 + dynamicScore * 0.2
        return min(1.0, max(0.0, excitement))
    }
    
    /// Analyze multiple clips and assign suggested ratings based on relative scoring
    static func analyzeAndRate(clips: [Clip]) async -> [(UUID, Int)] {
        guard !clips.isEmpty else { return [] }
        
        // Analyze all clips
        var scores: [(UUID, Double)] = []
        for clip in clips {
            let score = await analyzeExcitement(url: clip.url)
            scores.append((clip.id, score))
        }
        
        // Sort by score descending
        scores.sort { $0.1 > $1.1 }
        
        // Assign ratings by percentile
        // Top 10% → 5, next 20% → 4, next 30% → 3, next 25% → 2, bottom 15% → 1
        let total = scores.count
        var results: [(UUID, Int)] = []
        
        for (index, (id, _)) in scores.enumerated() {
            let percentile = Double(index) / Double(total)
            let rating: Int
            if percentile < 0.10 {
                rating = 5
            } else if percentile < 0.30 {
                rating = 4
            } else if percentile < 0.60 {
                rating = 3
            } else if percentile < 0.85 {
                rating = 2
            } else {
                rating = 1
            }
            results.append((id, rating))
        }
        
        return results
    }
}
