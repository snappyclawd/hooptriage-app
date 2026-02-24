import SwiftUI

@main
struct RushCutApp: App {
    @StateObject private var store = ClipStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var license = LicenseManager()

    var body: some Scene {
        WindowGroup {
            Group {
                switch license.state {
                case .unknown, .validating:
                    // Splash / loading state while checking license
                    licenseCheckView

                case .licensed:
                    ContentView()
                        .environmentObject(store)
                        .environmentObject(settings)
                        .environmentObject(license)
                        .onAppear {
                            // Apply saved settings to store on launch
                            store.folderOrganization = FolderOrganization(rawValue: settings.defaultFolderOrganization) ?? .byTag
                            store.gridColumns = settings.defaultGridColumns
                            if settings.hasCustomTags {
                                store.availableTags = settings.defaultTags
                            }
                        }

                case .unlicensed, .expired, .error(_):
                    LicenseEntryView(license: license)
                }
            }
            .preferredColorScheme(settings.colorScheme)
            .tint(settings.accent)
            .task {
                await license.checkOnLaunch()
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Replace the default Edit > Undo/Redo with our own
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    store.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(store.undoStack.isEmpty)

                Button("Redo") {
                    store.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(store.redoStack.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(license)
                .preferredColorScheme(settings.colorScheme)
        }
    }

    /// Minimal loading view shown while verifying the license on launch.
    private var licenseCheckView: some View {
        VStack(spacing: 16) {
            RushCutLogo(size: 48)
                .foregroundStyle(.orange)
            ProgressView()
                .controlSize(.small)
            Text("Verifying license...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
