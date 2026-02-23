import SwiftUI

/// Custom tag picker with wrapping pill layout and keyboard navigation
struct TagPickerView: View {
    let availableTags: [String]
    let selectedTags: Set<String>
    let onToggleTag: (String) -> Void
    let onAddTag: (String) -> Void
    let onDismiss: () -> Void
    
    @State private var focusedIndex: Int = 0
    @State private var newTagText = ""
    @State private var isAddingNew = false
    @FocusState private var isPickerFocused: Bool
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Tags")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                Text("↵ done")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            
            // Wrapping pill grid
            FlowLayout(spacing: 8) {
                ForEach(Array(availableTags.enumerated()), id: \.element) { index, tag in
                    tagPill(tag: tag, index: index)
                }
                
                // Add new tag button
                addNewPill
            }
            
            // New tag input (shown when adding)
            if isAddingNew {
                HStack(spacing: 8) {
                    TextField("New tag name...", text: $newTagText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            submitNewTag()
                        }
                        .onExitCommand {
                            isAddingNew = false
                            isPickerFocused = true
                        }
                    
                    Button("Add") {
                        submitNewTag()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        .focusable()
        .focused($isPickerFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            moveFocus(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveFocus(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveFocus(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveFocus(by: 1)
            return .handled
        }
        .onKeyPress(.space) {
            if !isAddingNew && focusedIndex < availableTags.count {
                onToggleTag(availableTags[focusedIndex])
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.return) {
            if !isAddingNew {
                onDismiss()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onAppear {
            isPickerFocused = true
        }
        .animation(.easeInOut(duration: 0.15), value: isAddingNew)
    }
    
    // MARK: - Tag Pill
    
    private func tagPill(tag: String, index: Int) -> some View {
        let isSelected = selectedTags.contains(tag)
        let isFocused = focusedIndex == index && !isAddingNew
        let color = tagColor(for: tag)
        
        return Text(tag)
            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color : color.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isFocused)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .onTapGesture {
                focusedIndex = index
                onToggleTag(tag)
                isPickerFocused = true
            }
            .onHover { hovering in
                if hovering { focusedIndex = index }
            }
    }
    
    // MARK: - Add New Pill
    
    private var addNewPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
            Text("New")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    focusedIndex == availableTags.count && !isAddingNew ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        )
        .onTapGesture {
            isAddingNew = true
            isTextFieldFocused = true
        }
    }
    
    // MARK: - Helpers
    
    private func moveFocus(by delta: Int) {
        let maxIndex = availableTags.count  // includes the "New" button
        focusedIndex = max(0, min(maxIndex, focusedIndex + delta))
    }
    
    private func submitNewTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespaces)
        if !tag.isEmpty {
            onAddTag(tag)
            onToggleTag(tag)
            newTagText = ""
        }
        isAddingNew = false
        isPickerFocused = true
    }
    
    private func tagColor(for tag: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .teal, .indigo, .mint, .cyan]
        let hash = abs(tag.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Flow Layout (wrapping horizontal layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }
    
    private struct ArrangementResult {
        var positions: [CGPoint]
        var size: CGSize
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }
        
        return ArrangementResult(
            positions: positions,
            size: CGSize(width: maxX, height: currentY + rowHeight)
        )
    }
}
