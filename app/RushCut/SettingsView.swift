import SwiftUI

/// App Settings / Preferences window
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var license: LicenseManager
    
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            TagsSettingsTab()
                .environmentObject(settings)
                .tabItem {
                    Label("Tags", systemImage: "tag")
                }
            
            AudioTriageSettingsTab()
                .environmentObject(settings)
                .tabItem {
                    Label("Audio Triage", systemImage: "waveform")
                }
            
            AppearanceSettingsTab()
                .environmentObject(settings)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            LicenseSettingsTab()
                .environmentObject(license)
                .tabItem {
                    Label("License", systemImage: "key")
                }
        }
        .frame(width: 450, height: 380)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    
    private var folderOrg: Binding<FolderOrganization> {
        Binding(
            get: { FolderOrganization(rawValue: settings.defaultFolderOrganization) ?? .byTag },
            set: { settings.defaultFolderOrganization = $0.rawValue }
        )
    }
    
    var body: some View {
        Form {
            Picker("Default folder organization", selection: folderOrg) {
                ForEach(FolderOrganization.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200, alignment: .leading)
            
            Picker("Default grid columns", selection: $settings.defaultGridColumns) {
                ForEach(1...6, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240, alignment: .leading)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Tags

struct TagsSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var newTagText = ""
    @State private var editingTags: [String] = []
    @State private var didLoad = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Default tags available when triaging clips. Changes apply to new sessions.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            // Tag pills
            FlowLayout(spacing: 6) {
                ForEach(editingTags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                        Button(action: { removeTag(tag) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
                }
            }
            
            // Add new tag
            HStack(spacing: 8) {
                TextField("New tag name", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit { addTag() }
                
                Button("Add") { addTag() }
                    .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            
            Spacer()
            
            // Reset
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetTagsToDefaults()
                    editingTags = settings.defaultTags
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            if !didLoad {
                editingTags = settings.defaultTags
                didLoad = true
            }
        }
    }
    
    private func addTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !editingTags.contains(trimmed) else { return }
        editingTags.append(trimmed)
        settings.defaultTags = editingTags
        newTagText = ""
    }
    
    private func removeTag(_ tag: String) {
        editingTags.removeAll { $0 == tag }
        settings.defaultTags = editingTags
    }
}

// MARK: - Audio Triage

struct AudioTriageSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    
    var body: some View {
        Form {
            Section("Loud Group") {
                TextField("Label", text: $settings.audioLoudLabel)
                    .frame(width: 200)
                
                HStack {
                    Text("Top")
                    Slider(value: $settings.audioLoudPercentage, in: 5...50, step: 5)
                        .frame(width: 150)
                    Text("\(Int(settings.audioLoudPercentage))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
            
            Section("Quiet Group") {
                TextField("Label", text: $settings.audioQuietLabel)
                    .frame(width: 200)
                
                HStack {
                    Text("Bottom")
                    Slider(value: $settings.audioQuietPercentage, in: 5...50, step: 5)
                        .frame(width: 150)
                    Text("\(Int(settings.audioQuietPercentage))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance

struct AppearanceSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    
    var body: some View {
        Form {
            // Appearance mode
            Picker("Appearance", selection: Binding(
                get: { settings.appearanceMode },
                set: { settings.appearanceMode = $0 }
            )) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220, alignment: .leading)
            
            // Theme color
            VStack(alignment: .leading, spacing: 10) {
                Text("Accent color")
                
                HStack(spacing: 10) {
                    ForEach(ThemeColor.allCases) { theme in
                        Button(action: { settings.themeColor = theme }) {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: settings.themeColor == theme ? 2.5 : 0)
                                        .padding(settings.themeColor == theme ? -2 : 0)
                                )
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .opacity(settings.themeColor == theme ? 1 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(theme.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - License

struct LicenseSettingsTab: View {
    @EnvironmentObject var license: LicenseManager
    @State private var showDeactivateConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Status
            HStack(spacing: 8) {
                Image(systemName: license.state == .licensed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .foregroundStyle(license.state == .licensed ? .green : .red)
                    .font(.system(size: 16))
                Text(license.state == .licensed ? "License active" : "Not licensed")
                    .font(.system(size: 14, weight: .semibold))
            }

            // License key (masked)
            if let key = license.licenseKey {
                VStack(alignment: .leading, spacing: 4) {
                    Text("License key")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(maskedKey(key))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            Divider()

            // Deactivate
            VStack(alignment: .leading, spacing: 6) {
                Text("Deactivate this Mac to free up your license for another machine.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Button("Deactivate License...", role: .destructive) {
                    showDeactivateConfirm = true
                }
            }

            Spacer()
        }
        .padding()
        .confirmationDialog(
            "Deactivate license on this Mac?",
            isPresented: $showDeactivateConfirm,
            titleVisibility: .visible
        ) {
            Button("Deactivate", role: .destructive) {
                Task { await license.deactivate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will sign you out and free up an activation slot. You'll need to re-enter your license key to use RushCut on this Mac again.")
        }
    }

    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return key }
        let prefix = String(key.prefix(8))
        let suffix = String(key.suffix(6))
        return "\(prefix)...\(suffix)"
    }
}

// FlowLayout is defined in TagPickerView.swift and shared across the app
