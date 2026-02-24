import Foundation
import AVFoundation

/// Raw audio metrics for a single clip
struct AudioMetrics {
    let maxRMS: Float       // Peak loudness (max of 100ms RMS windows)
    let avgRMS: Float       // Average loudness across all windows
    let spikeRatio: Float   // Fraction of windows exceeding 2x average
    let dynamicRange: Float // Difference between 90th and 10th percentile RMS
    let peakAmplitude: Float // Absolute peak sample value
    
    /// A single 0-1 "excitement" score combining all metrics
    var excitement: Double {
        let loudnessScore = min(1.0, Double(maxRMS) / 0.3)
        let spikeScore = min(1.0, Double(spikeRatio) / 0.15)
        let dynamicScore = min(1.0, Double(dynamicRange) / 0.15)
        return min(1.0, max(0.0, loudnessScore * 0.5 + spikeScore * 0.3 + dynamicScore * 0.2))
    }
    
    static let zero = AudioMetrics(maxRMS: 0, avgRMS: 0, spikeRatio: 0, dynamicRange: 0, peakAmplitude: 0)
}

/// Analyzes audio tracks of video clips to extract loudness metrics
struct AudioAnalyzer {
    
    /// Analyze a single clip's audio and return raw metrics
    static func analyze(url: URL) async -> AudioMetrics {
        let asset = AVURLAsset(url: url)
        
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            return .zero // No audio track
        }
        
        // Read audio samples
        guard let reader = try? AVAssetReader(asset: asset) else { return .zero }
        
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
        
        guard reader.startReading() else { return .zero }
        
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
        
        guard allSamples.count > 0 else { return .zero }
        
        // Peak amplitude
        let peakAmplitude = allSamples.map { abs($0) }.max() ?? 0
        
        // Calculate metrics in windows (100ms windows at 16kHz = 1600 samples)
        let windowSize = 1600
        let windowCount = allSamples.count / windowSize
        guard windowCount > 0 else {
            return AudioMetrics(maxRMS: 0, avgRMS: 0, spikeRatio: 0, dynamicRange: 0, peakAmplitude: peakAmplitude)
        }
        
        var windowRMS: [Float] = []
        
        for i in 0..<windowCount {
            let start = i * windowSize
            let end = min(start + windowSize, allSamples.count)
            let window = allSamples[start..<end]
            
            // RMS (loudness)
            let sumSquares = window.reduce(0.0) { $0 + $1 * $1 }
            let rms = sqrt(sumSquares / Float(window.count))
            windowRMS.append(rms)
        }
        
        // Overall metrics
        let avgRMS = windowRMS.reduce(0, +) / Float(windowRMS.count)
        let maxRMS = windowRMS.max() ?? 0
        
        // Dynamic range: how much variation between quiet and loud parts
        let sortedRMS = windowRMS.sorted()
        let p10 = sortedRMS[Int(Float(sortedRMS.count) * 0.1)]
        let p90 = sortedRMS[min(Int(Float(sortedRMS.count) * 0.9), sortedRMS.count - 1)]
        let dynamicRange = p90 - p10
        
        // Spike count: windows that are significantly louder than average
        let spikeThreshold = avgRMS * 2.0
        let spikeCount = windowRMS.filter { $0 > spikeThreshold }.count
        let spikeRatio = Float(spikeCount) / Float(windowCount)
        
        return AudioMetrics(
            maxRMS: maxRMS,
            avgRMS: avgRMS,
            spikeRatio: spikeRatio,
            dynamicRange: dynamicRange,
            peakAmplitude: peakAmplitude
        )
    }
}
