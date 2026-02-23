import SwiftUI

/// Dialog for running audio triage — explains, shows progress, then results
struct AudioTriageView: View {
    @ObservedObject var store: ClipStore
    let onDismiss: () -> Void
    
    enum Phase {
        case ready
        case analyzing
        case complete
    }
    
    @State private var phase: Phase = .ready
    @State private var currentClipIndex = 0
    @State private var currentClipName = ""
    @State private var totalToAnalyze = 0
    @State private var suggestionsApplied = 0
    
    private var unratedClips: [Clip] {
        store.clips.filter { $0.rating == 0 && $0.suggestedRating == 0 }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Audio Triage")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                if phase != .analyzing {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            
            Divider()
            
            switch phase {
            case .ready:
                readyView
            case .analyzing:
                analyzingView
            case .complete:
                completeView
            }
        }
        .frame(width: 460)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Ready
    
    private var readyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Explanation
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Analyze audio to suggest ratings")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Pre-qualify clips for your review")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    explanationRow(icon: "speaker.wave.3", text: "Scans each clip's audio for crowd noise, cheering, and energy spikes")
                    explanationRow(icon: "chart.bar", text: "Ranks clips relative to each other — loudest moments get higher ratings")
                    explanationRow(icon: "eye", text: "Ratings are **suggestions** only — you review and accept or dismiss each one")
                    explanationRow(icon: "arrow.uturn.backward", text: "Fully undoable with ⌘Z")
                }
                .padding(.top, 4)
            }
            
            Divider()
            
            // What will happen
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("\(unratedClips.count)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                    Text("clips to analyze")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 2) {
                    Text("\(store.clips.count - unratedClips.count)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                    Text("already rated")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            
            if unratedClips.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                    Text("All clips already have ratings!")
                        .font(.system(size: 13))
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            // Buttons
            HStack {
                Spacer()
                
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(action: startAnalysis) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                        Text("Analyze \(unratedClips.count) Clips")
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(unratedClips.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
    
    // MARK: - Analyzing
    
    private var analyzingView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // Waveform animation placeholder
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
                .symbolEffect(.pulse)
            
            Text("Analyzing audio…")
                .font(.system(size: 16, weight: .semibold))
            
            // Progress
            VStack(spacing: 8) {
                ProgressView(value: totalToAnalyze > 0 ? Double(currentClipIndex) / Double(totalToAnalyze) : 0)
                    .progressViewStyle(.linear)
                
                HStack {
                    Text(currentClipName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Text("\(currentClipIndex) / \(totalToAnalyze)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .padding(20)
    }
    
    // MARK: - Complete
    
    private var completeView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("Analysis Complete!")
                .font(.system(size: 16, weight: .semibold))
            
            Text("\(suggestionsApplied) clips received suggested ratings")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Next steps:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                explanationRow(icon: "eye", text: "Review the blue suggested ratings on each card")
                explanationRow(icon: "checkmark.circle", text: "**Accept** or **Dismiss** individually, or use **Accept All**")
                explanationRow(icon: "hand.tap", text: "Set your own rating to override any suggestion")
            }
            .padding(.top, 4)
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
    
    // MARK: - Actions
    
    private func startAnalysis() {
        let clips = unratedClips
        totalToAnalyze = clips.count
        currentClipIndex = 0
        phase = .analyzing
        
        Task {
            // Analyze each clip with progress updates
            var scores: [(UUID, Double)] = []
            
            for (index, clip) in clips.enumerated() {
                currentClipIndex = index + 1
                currentClipName = clip.filename
                
                let score = await AudioAnalyzer.analyzeExcitement(url: clip.url)
                scores.append((clip.id, score))
            }
            
            // Sort and assign ratings by percentile
            scores.sort { $0.1 > $1.1 }
            let total = scores.count
            var applied: [(UUID, Int)] = []
            
            for (index, (id, _)) in scores.enumerated() {
                let percentile = Double(index) / Double(max(total, 1))
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
                
                if let idx = store.clips.firstIndex(where: { $0.id == id }) {
                    store.clips[idx].suggestedRating = rating
                    applied.append((id, rating))
                }
            }
            
            suggestionsApplied = applied.count
            
            if !applied.isEmpty {
                // Push undo via store (access internal method)
                store.pushUndoAction(.audioTriage(suggestions: applied))
            }
            
            // Auto-switch to rating grouping if no grouping is active
            if store.groupMode == .none {
                store.groupMode = .rating
            }
            
            phase = .complete
        }
    }
    
    // MARK: - Helpers
    
    private func explanationRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.8))
        }
    }
}
