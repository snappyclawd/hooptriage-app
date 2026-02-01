import SwiftUI

@main
struct HoopTriageApp: App {
    @StateObject private var store = ClipStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
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
    }
}
