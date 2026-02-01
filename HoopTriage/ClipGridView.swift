import SwiftUI

/// The main grid of clip thumbnails
struct ClipGridView: View {
    @ObservedObject var store: ClipStore
    @State private var expandedClip: Clip? = nil
    
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
                            onRate: { rating in
                                store.setRating(rating, for: clip.id)
                            },
                            onDoubleClick: {
                                expandedClip = clip
                            }
                        )
                    }
                }
                .padding(12)
            }
            
            // Expanded player overlay
            if let clip = expandedClip {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { expandedClip = nil }
                
                PlayerView(clip: clip) {
                    expandedClip = nil
                }
                .frame(maxWidth: 900)
                .padding(40)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expandedClip?.id)
    }
}
