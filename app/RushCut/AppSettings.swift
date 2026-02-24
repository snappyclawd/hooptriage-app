import SwiftUI

// MARK: - App Theme Colors

/// Available theme colors for the app accent
enum ThemeColor: String, CaseIterable, Identifiable {
    case orange = "Orange"
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case red = "Red"
    case green = "Green"
    case teal = "Teal"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .orange: return .orange
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .green: return .green
        case .teal: return .teal
        }
    }
}

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - App Settings

/// Centralized app settings backed by UserDefaults via @AppStorage.
/// Injected as an @EnvironmentObject so all views can read theme/preferences.
final class AppSettings: ObservableObject {
    
    // MARK: General
    
    @AppStorage("defaultFolderOrganization")
    var defaultFolderOrganization: String = FolderOrganization.byTag.rawValue
    
    @AppStorage("defaultGridColumns")
    var defaultGridColumns: Int = 3
    
    // MARK: Tags
    
    /// Stored as a JSON-encoded array of strings
    @AppStorage("customDefaultTags")
    var customDefaultTagsJSON: String = ""
    
    /// Whether the user has customized tags (vs using the built-in defaults)
    @AppStorage("hasCustomTags")
    var hasCustomTags: Bool = false
    
    /// Computed property to get/set the tags as an array
    var defaultTags: [String] {
        get {
            if hasCustomTags, !customDefaultTagsJSON.isEmpty,
               let data = customDefaultTagsJSON.data(using: .utf8),
               let tags = try? JSONDecoder().decode([String].self, from: data) {
                return tags
            }
            return builtInDefaultTags
        }
        set {
            hasCustomTags = true
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                customDefaultTagsJSON = json
            }
            objectWillChange.send()
        }
    }
    
    // MARK: Audio Triage Defaults
    
    @AppStorage("audioLoudLabel")
    var audioLoudLabel: String = "Loud Peaks"
    
    @AppStorage("audioLoudPercentage")
    var audioLoudPercentage: Double = 15
    
    @AppStorage("audioQuietLabel")
    var audioQuietLabel: String = "Quiet"
    
    @AppStorage("audioQuietPercentage")
    var audioQuietPercentage: Double = 15
    
    // MARK: Appearance
    
    @AppStorage("appearanceMode")
    var appearanceModeRaw: String = AppearanceMode.system.rawValue
    
    @AppStorage("themeColor")
    var themeColorRaw: String = ThemeColor.orange.rawValue
    
    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue }
    }
    
    var themeColor: ThemeColor {
        get { ThemeColor(rawValue: themeColorRaw) ?? .orange }
        set { themeColorRaw = newValue.rawValue }
    }
    
    /// The resolved accent color for the current theme
    var accent: Color {
        themeColor.color
    }
    
    /// The resolved color scheme (nil = follow system)
    var colorScheme: ColorScheme? {
        appearanceMode.colorScheme
    }
    
    // MARK: Helpers
    
    func resetTagsToDefaults() {
        hasCustomTags = false
        customDefaultTagsJSON = ""
        objectWillChange.send()
    }
}

/// The built-in default tags (basketball-themed)
let builtInDefaultTags = [
    "Action",
    "Three",
    "Dunk",
    "Huddle",
    "Warmup",
    "Establishment",
    "Interview",
    "Celebration",
    "Defense",
    "Fast Break",
]
