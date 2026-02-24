import SwiftUI

/// Dialog for running audio triage — analyzes loudness, then lets users
/// configure "Loud Peaks" and "Quiet" groups before applying as tags.
struct AudioTriageView: View {
    @ObservedObject var store: ClipStore
    @EnvironmentObject var settings: AppSettings
    let onDismiss: () -> Void
    
    enum Phase {
        case ready
        case analyzing
        case results
    }
    
    @State private var phase: Phase = .ready
    @State private var currentClipIndex = 0
    @State private var currentClipName = ""
    @State private var totalToAnalyze = 0
    @State private var didLoadSettings = false
    
    // Analysis results — sorted by excitement descending
    @State private var sortedResults: [(clip: Clip, metrics: AudioMetrics)] = []
    
    // Loud group config (defaults overridden from settings on appear)
    @State private var loudEnabled = true
    @State private var loudLabel = "Loud Peaks"
    @State private var loudMode: SelectionMode = .percentage
    @State private var loudPercentage: Double = 15  // top N%
    @State private var loudThreshold: Double = 0.25 // maxRMS threshold
    
    // Quiet group config (defaults overridden from settings on appear)
    @State private var quietEnabled = true
    @State private var quietLabel = "Quiet"
    @State private var quietMode: SelectionMode = .percentage
    @State private var quietPercentage: Double = 15 // bottom N%
    @State private var quietThreshold: Double = 0.05 // maxRMS threshold
    
    enum SelectionMode: String, CaseIterable {
        case percentage = "Top/Bottom %"
        case threshold = "Threshold"
    }
    
    private var unanalyzedClips: [Clip] {
        store.clips.filter { store.audioMetrics[$0.id] == nil }
    }
    
    // MARK: - Computed clip sets
    
    private var loudClipCount: Int {
        guard loudEnabled else { return 0 }
        switch loudMode {
        case .percentage:
            return min(sortedResults.count, max(1, Int(ceil(Double(sortedResults.count) * loudPercentage / 100.0))))
        case .threshold:
            return sortedResults.filter { Double($0.metrics.maxRMS) >= loudThreshold }.count
        }
    }
    
    private var quietClipCount: Int {
        guard quietEnabled else { return 0 }
        switch quietMode {
        case .percentage:
            return min(sortedResults.count, max(1, Int(ceil(Double(sortedResults.count) * quietPercentage / 100.0))))
        case .threshold:
            return sortedResults.filter { Double($0.metrics.maxRMS) <= quietThreshold }.count
        }
    }
    
    private var middleClipCount: Int {
        max(0, sortedResults.count - loudClipCount - quietClipCount)
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
            case .results:
                resultsView
            }
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .cornerRadius(12)
        .onAppear {
            guard !didLoadSettings else { return }
            didLoadSettings = true
            loudLabel = settings.audioLoudLabel
            loudPercentage = settings.audioLoudPercentage
            quietLabel = settings.audioQuietLabel
            quietPercentage = settings.audioQuietPercentage
        }
    }
    
    // MARK: - Ready
    
    private var readyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Analyze audio loudness")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Identify loud highlights and quiet b-roll")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    explanationRow(icon: "speaker.wave.3", text: "Scans each clip's audio for loudness levels and peak spikes")
                    explanationRow(icon: "tag", text: "Tags clips as **Loud Peaks** or **Quiet** — you choose the thresholds")
                    explanationRow(icon: "slider.horizontal.3", text: "Middle clips are left untouched — the value is in the extremes")
                    explanationRow(icon: "arrow.uturn.backward", text: "Fully undoable with Cmd+Z")
                }
                .padding(.top, 4)
            }
            
            Divider()
            
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("\(store.clips.count)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                    Text("clips to analyze")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            
            if store.clips.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(settings.accent)
                    Text("No clips loaded yet!")
                        .font(.system(size: 13))
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button(action: startAnalysis) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                        Text("Analyze \(store.clips.count) Clips")
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.clips.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
    
    // MARK: - Analyzing
    
    private var analyzingView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
                .symbolEffect(.pulse)
            
            Text("Analyzing audio...")
                .font(.system(size: 16, weight: .semibold))
            
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
    
    // MARK: - Results
    
    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
                Text("Analysis complete — \(sortedResults.count) clips ranked by loudness")
                    .font(.system(size: 13, weight: .medium))
            }
            
            Divider()
            
            // Loud Peaks group
            groupConfigSection(
                icon: "speaker.wave.3.fill",
                color: settings.accent,
                title: "Loud Peaks",
                subtitle: "Clips with the highest audio energy — crowd noise, cheering, big moments",
                enabled: $loudEnabled,
                label: $loudLabel,
                mode: $loudMode,
                percentage: $loudPercentage,
                threshold: $loudThreshold,
                clipCount: loudClipCount,
                isLoud: true
            )
            
            Divider()
            
            // Quiet group
            groupConfigSection(
                icon: "speaker.fill",
                color: .blue,
                title: "Quiet",
                subtitle: "Clips with consistently low volume — b-roll, timeouts, establishing shots",
                enabled: $quietEnabled,
                label: $quietLabel,
                mode: $quietMode,
                percentage: $quietPercentage,
                threshold: $quietThreshold,
                clipCount: quietClipCount,
                isLoud: false
            )
            
            Divider()
            
            // Summary of what will happen
            VStack(alignment: .leading, spacing: 4) {
                if loudEnabled {
                    Label("\(loudClipCount) clips will be tagged \"\(loudLabel)\"", systemImage: "tag.fill")
                        .font(.system(size: 12))
                        .foregroundColor(settings.accent)
                }
                if quietEnabled {
                    Label("\(quietClipCount) clips will be tagged \"\(quietLabel)\"", systemImage: "tag.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
                Label("\(middleClipCount) clips left untouched", systemImage: "minus.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button(action: applyTags) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                        Text("Apply Tags")
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(settings.accent)
                .disabled(!loudEnabled && !quietEnabled)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
    
    // MARK: - Group Config Section
    
    private func groupConfigSection(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        enabled: Binding<Bool>,
        label: Binding<String>,
        mode: Binding<SelectionMode>,
        percentage: Binding<Double>,
        threshold: Binding<Double>,
        clipCount: Int,
        isLoud: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with toggle
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(enabled.wrappedValue ? color : .secondary)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            
            if enabled.wrappedValue {
                // Tag label
                HStack(spacing: 8) {
                    Text("Tag label:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("Label", text: label)
                        .font(.system(size: 12))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 150)
                }
                
                // Mode picker
                Picker("", selection: mode) {
                    ForEach(SelectionMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                // Slider
                HStack(spacing: 10) {
                    if mode.wrappedValue == .percentage {
                        Text(isLoud ? "Top" : "Bottom")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        
                        Slider(value: percentage, in: 5...50, step: 5)
                        
                        Text("\(Int(percentage.wrappedValue))%")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .frame(width: 36, alignment: .trailing)
                    } else {
                        Text("Peak RMS \(isLoud ? ">" : "<")")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 72, alignment: .trailing)
                        
                        Slider(value: threshold, in: 0.01...0.5, step: 0.01)
                        
                        Text(String(format: "%.2f", threshold.wrappedValue))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                
                // Clip count result
                HStack(spacing: 4) {
                    Text("\(clipCount)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                    Text("clip\(clipCount == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(enabled.wrappedValue ? color.opacity(0.05) : Color.clear)
        .cornerRadius(10)
        .animation(.easeInOut(duration: 0.15), value: enabled.wrappedValue)
    }
    
    // MARK: - Actions
    
    private func startAnalysis() {
        let clips = store.clips
        totalToAnalyze = clips.count
        currentClipIndex = 0
        phase = .analyzing
        
        Task {
            var results: [(clip: Clip, metrics: AudioMetrics)] = []
            
            for (index, clip) in clips.enumerated() {
                currentClipIndex = index + 1
                currentClipName = clip.filename
                
                // Use cached metrics if available
                let metrics: AudioMetrics
                if let cached = store.audioMetrics[clip.id] {
                    metrics = cached
                } else {
                    metrics = await AudioAnalyzer.analyze(url: clip.url)
                    store.audioMetrics[clip.id] = metrics
                }
                results.append((clip: clip, metrics: metrics))
            }
            
            // Sort by excitement score descending (loudest first)
            results.sort { $0.metrics.excitement > $1.metrics.excitement }
            sortedResults = results
            
            // Set sensible defaults based on actual data
            if let loudestRMS = results.first?.metrics.maxRMS {
                loudThreshold = Double(loudestRMS) * 0.7
            }
            if let quietestRMS = results.last?.metrics.maxRMS {
                quietThreshold = max(0.01, Double(quietestRMS) * 2.0)
            }
            
            phase = .results
        }
    }
    
    private func applyTags() {
        var tagsToApply: [(UUID, String)] = []
        
        if loudEnabled && loudClipCount > 0 {
            let loudClips: ArraySlice<(clip: Clip, metrics: AudioMetrics)>
            switch loudMode {
            case .percentage:
                loudClips = sortedResults.prefix(loudClipCount)
            case .threshold:
                loudClips = sortedResults.prefix(while: { Double($0.metrics.maxRMS) >= loudThreshold })
            }
            for item in loudClips {
                tagsToApply.append((item.clip.id, loudLabel))
            }
        }
        
        if quietEnabled && quietClipCount > 0 {
            let quietClips: ArraySlice<(clip: Clip, metrics: AudioMetrics)>
            switch quietMode {
            case .percentage:
                quietClips = sortedResults.suffix(quietClipCount)
            case .threshold:
                // Quiet clips from the bottom
                quietClips = sortedResults.suffix(
                    sortedResults.reversed().prefix(while: { Double($0.metrics.maxRMS) <= quietThreshold }).count
                )
            }
            for item in quietClips {
                // Don't double-tag if already in loud group
                if !tagsToApply.contains(where: { $0.0 == item.clip.id }) {
                    tagsToApply.append((item.clip.id, quietLabel))
                }
            }
        }
        
        store.applyAudioTriageTags(tags: tagsToApply)
        
        // Auto-switch to tag grouping
        if store.groupMode == .none {
            store.groupMode = .category
        }
        
        // Auto-switch folder organization to "By Tag" since we just applied tags
        store.folderOrganization = .byTag
        
        onDismiss()
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
