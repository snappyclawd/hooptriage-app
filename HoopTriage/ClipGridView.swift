import SwiftUI

/// The main grid of clip thumbnails
struct ClipGridView: View {
    @ObservedObject var store: ClipStore
    let audioEnabled: Bool
    @State private var expandedClip: Clip? = nil
    @State private var pinchScale: CGFloat = 1.0
    
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: store.gridColumns)
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.sortedAndFilteredClips) { clip in
                        ClipThumbnailView(
                            clip: clip,
                            thumbnailGenerator: store.thumbnailGenerator,
                            availableTags: store.availableTags,
                            audioEnabled: audioEnabled,
                            onRate: { rating in
                                store.setRating(rating, for: clip.id)
                            },
                            onTag: { tag in
                                store.setCategory(tag, for: clip.id)
                            },
                            onAddTag: { tag in
                                store.addTag(tag)
                            },
                            onDoubleClick: {
                                expandedClip = clip
                            }
                        )
                    }
                }
                .padding(12)
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        pinchScale = value.magnification
                    }
                    .onEnded { value in
                        let delta = value.magnification
                        if delta > 1.2 {
                            // Pinch out = bigger tiles = fewer columns
                            store.gridColumns = max(1, store.gridColumns - 1)
                        } else if delta < 0.8 {
                            // Pinch in = smaller tiles = more columns
                            store.gridColumns = min(5, store.gridColumns + 1)
                        }
                        pinchScale = 1.0
                    }
            )
            
            // Expanded player overlay
            if let clip = expandedClip {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { expandedClip = nil }
                
                PlayerView(clip: clip) {
                    expandedClip = nil
                }
                .frame(maxWidth: 1000, maxHeight: 700)
                .padding(40)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expandedClip?.id)
        .animation(.easeInOut(duration: 0.15), value: store.gridColumns)
    }
}
