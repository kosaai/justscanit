import SwiftUI
import UIKit

struct ReorderPagesView: View {
    let pages: [ScannedPage]
    let onDone: ([ScannedPage]) -> Void
    let onCancel: () -> Void
    let onDeletePage: (UUID) -> Void

    @State private var reorderedPages: [ScannedPage] = []
    @State private var draggedPageId: UUID?
    @State private var dragStartPosition: CGPoint = .zero
    @State private var currentDragPosition: CGPoint = .zero
    @State private var isDragging = false
    @State private var showDeleteConfirm = false
    @State private var pageToDelete: ScannedPage?

    private let columns = 3
    private let spacing: CGFloat = 16
    private let horizontalPadding: CGFloat = 16
    private let verticalSpacing: CGFloat = 40
    private let topPadding: CGFloat = 20

    // Slight offset when picking up to show it's lifted
    private let pickupOffset = CGSize(width: 12, height: -12)

    // Animation duration for grid reordering (slower = smoother feel)
    private let reorderAnimationDuration: Double = 0.35

    var body: some View {
        GeometryReader { geometry in
            let itemWidth = calculateItemWidth(screenWidth: geometry.size.width)
            let itemHeight = itemWidth * 1.4

            ZStack {
                Color(UIColor.systemGray6)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Divider()

                    ScrollView {
                        gridContent(itemWidth: itemWidth, itemHeight: itemHeight)
                    }
                }

                // Dragged item overlay - follows finger exactly
                if isDragging, let draggedId = draggedPageId,
                   let page = reorderedPages.first(where: { $0.id == draggedId }) {
                    DraggedPageOverlay(
                        page: page,
                        itemWidth: itemWidth,
                        itemHeight: itemHeight,
                        position: CGPoint(
                            x: currentDragPosition.x + pickupOffset.width,
                            y: currentDragPosition.y + pickupOffset.height
                        )
                    )
                }
            }
        }
        .alert("Delete Page?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {
                pageToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let page = pageToDelete {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        reorderedPages.removeAll { $0.id == page.id }
                    }
                    onDeletePage(page.id)
                }
                pageToDelete = nil
            }
        } message: {
            Text("This page will be permanently removed from the document.")
        }
        .onAppear {
            reorderedPages = pages
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .foregroundColor(.blue)

            Spacer()

            Text("Reorder")
                .font(.headline)

            Spacer()

            Button("Done") {
                onDone(reorderedPages)
            }
            .foregroundColor(.blue)
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Grid Content

    private func gridContent(itemWidth: CGFloat, itemHeight: CGFloat) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns),
            spacing: verticalSpacing
        ) {
            ForEach(Array(reorderedPages.enumerated()), id: \.element.id) { index, page in
                pageCellWithGestures(page: page, index: index, itemWidth: itemWidth, itemHeight: itemHeight)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, 40)
    }

    private func pageCellWithGestures(page: ScannedPage, index: Int, itemWidth: CGFloat, itemHeight: CGFloat) -> some View {
        PageCell(
            page: page,
            index: index,
            itemWidth: itemWidth,
            itemHeight: itemHeight,
            isBeingDragged: draggedPageId == page.id,
            isAnyDragging: isDragging,
            onDelete: {
                pageToDelete = page
                showDeleteConfirm = true
            }
        )
        .animation(.easeInOut(duration: reorderAnimationDuration), value: reorderedPages.map { $0.id })
        .gesture(
            LongPressGesture(minimumDuration: 0.2)
                .sequenced(before: DragGesture(coordinateSpace: .global))
                .onChanged { value in
                    switch value {
                    case .first(true):
                        // Long press recognized - prepare for drag
                        break
                    case .second(true, let drag):
                        if let drag = drag {
                            if !isDragging {
                                // Start drag
                                startDrag(page: page, at: drag.location)
                            } else if draggedPageId == page.id {
                                // Continue drag
                                handleDrag(
                                    location: drag.location,
                                    itemWidth: itemWidth,
                                    itemHeight: itemHeight
                                )
                            }
                        }
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    endDrag()
                }
        )
    }

    // MARK: - Position Calculation

    private func calculateItemWidth(screenWidth: CGFloat) -> CGFloat {
        let totalSpacing = spacing * CGFloat(columns - 1)
        let totalPadding = horizontalPadding * 2
        return (screenWidth - totalSpacing - totalPadding) / CGFloat(columns)
    }

    private func indexAtPosition(_ position: CGPoint, itemWidth: CGFloat, itemHeight: CGFloat) -> Int? {
        let cellHeight = itemHeight + 24 // page number label
        let totalCellWidth = itemWidth + spacing
        let totalCellHeight = cellHeight + verticalSpacing

        // Adjust for grid origin (approximate - we're in global coordinates)
        // The grid starts after top bar (~56pt) + divider + topPadding
        let gridTopOffset: CGFloat = 56 + topPadding
        let adjustedX = position.x - horizontalPadding
        let adjustedY = position.y - gridTopOffset

        guard adjustedX >= 0, adjustedY >= 0 else { return nil }

        let col = Int((adjustedX + totalCellWidth / 2) / totalCellWidth)
        let row = Int((adjustedY + totalCellHeight / 2) / totalCellHeight)

        guard col >= 0, col < columns else { return nil }

        let index = row * columns + col
        guard index >= 0, index < reorderedPages.count else { return nil }

        return index
    }

    // MARK: - Drag Handling

    private func startDrag(page: ScannedPage, at location: CGPoint) {
        draggedPageId = page.id
        isDragging = true
        dragStartPosition = location
        currentDragPosition = location
    }

    private func handleDrag(location: CGPoint, itemWidth: CGFloat, itemHeight: CGFloat) {
        // Update drag position - this directly moves the overlay
        currentDragPosition = location

        guard let draggedId = draggedPageId,
              let currentIndex = reorderedPages.firstIndex(where: { $0.id == draggedId }) else { return }

        // Check position with pickup offset applied
        let testPosition = CGPoint(
            x: location.x + pickupOffset.width,
            y: location.y + pickupOffset.height
        )

        // Find target index based on drag position
        if let targetIndex = indexAtPosition(testPosition, itemWidth: itemWidth, itemHeight: itemHeight),
           targetIndex != currentIndex {
            // Reorder - only the grid animates, dragged item stays with finger
            withAnimation(.easeInOut(duration: reorderAnimationDuration)) {
                reorderedPages.move(
                    fromOffsets: IndexSet(integer: currentIndex),
                    toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex
                )
            }
        }
    }

    private func endDrag() {
        withAnimation(.easeOut(duration: 0.2)) {
            isDragging = false
            draggedPageId = nil
        }
    }
}

// MARK: - Page Cell

struct PageCell: View {
    let page: ScannedPage
    let index: Int
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let isBeingDragged: Bool
    let isAnyDragging: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                if isBeingDragged {
                    // Dotted placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                        .foregroundColor(.blue.opacity(0.5))
                        .frame(width: itemWidth, height: itemHeight)
                } else {
                    thumbnailImage

                    // Delete button - hidden during any drag
                    if !isAnyDragging {
                        deleteButton
                    }
                }
            }
            .frame(width: itemWidth, height: itemHeight)

            Text("\(index + 1)")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.blue)
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        let imagePath = page.croppedImagePath ?? page.originalImagePath
        if let image = DocumentStorage.shared.loadImage(filename: imagePath) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: itemWidth, height: itemHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .frame(width: itemWidth, height: itemHeight)
        }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 26, height: 26)
                Circle()
                    .strokeBorder(Color.blue, lineWidth: 1.5)
                    .frame(width: 26, height: 26)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.blue)
            }
        }
        .offset(x: -8, y: -8)
    }
}

// MARK: - Dragged Page Overlay

struct DraggedPageOverlay: View {
    let page: ScannedPage
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let position: CGPoint

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        let imagePath = page.croppedImagePath ?? page.originalImagePath
        if let image = DocumentStorage.shared.loadImage(filename: imagePath) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: itemWidth, height: itemHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
                .scaleEffect(pulseScale)
                .position(position)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.06
                    }
                }
        }
    }
}
