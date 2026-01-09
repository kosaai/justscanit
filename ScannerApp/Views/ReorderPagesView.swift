import SwiftUI
import UIKit

struct ReorderPagesView: View {
    let pages: [ScannedPage]
    let onDone: ([ScannedPage]) -> Void
    let onCancel: () -> Void
    let onDeletePage: (UUID) -> Void

    @State private var reorderedPages: [ScannedPage] = []
    @State private var draggedPageId: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var showDeleteConfirm = false
    @State private var pageToDelete: ScannedPage?
    @State private var gridOrigin: CGPoint = .zero

    private let columns = 3
    private let spacing: CGFloat = 16
    private let horizontalPadding: CGFloat = 16
    private let verticalSpacing: CGFloat = 40
    private let topPadding: CGFloat = 20

    // Initial offset when picking up item
    private let pickupOffset = CGSize(width: 15, height: -15)

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
                            .background(
                                GeometryReader { gridGeo in
                                    Color.clear.onAppear {
                                        gridOrigin = gridGeo.frame(in: .global).origin
                                    }
                                }
                            )
                    }
                }

                // Dragged item overlay
                if isDragging, let draggedId = draggedPageId,
                   let page = reorderedPages.first(where: { $0.id == draggedId }),
                   let index = reorderedPages.firstIndex(where: { $0.id == draggedId }) {
                    let basePosition = itemPosition(for: index, itemWidth: itemWidth, itemHeight: itemHeight)
                    DraggedPageOverlay(
                        page: page,
                        itemWidth: itemWidth,
                        itemHeight: itemHeight,
                        position: CGPoint(
                            x: basePosition.x + dragOffset.width + pickupOffset.width,
                            y: basePosition.y + dragOffset.height + pickupOffset.height
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
                .gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .onEnded { _ in
                            startDrag(page: page)
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if draggedPageId == page.id {
                                handleDrag(translation: value.translation, itemWidth: itemWidth, itemHeight: itemHeight)
                            }
                        }
                        .onEnded { _ in
                            endDrag()
                        }
                )
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, 40)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: reorderedPages.map { $0.id })
    }

    // MARK: - Position Calculation

    private func calculateItemWidth(screenWidth: CGFloat) -> CGFloat {
        let totalSpacing = spacing * CGFloat(columns - 1)
        let totalPadding = horizontalPadding * 2
        return (screenWidth - totalSpacing - totalPadding) / CGFloat(columns)
    }

    private func itemPosition(for index: Int, itemWidth: CGFloat, itemHeight: CGFloat) -> CGPoint {
        let row = index / columns
        let col = index % columns
        let cellHeight = itemHeight + 24 // Account for page number label
        let x = horizontalPadding + CGFloat(col) * (itemWidth + spacing) + itemWidth / 2
        let y = topPadding + CGFloat(row) * (cellHeight + verticalSpacing) + cellHeight / 2
        return CGPoint(x: x, y: y)
    }

    private func indexAtPosition(_ position: CGPoint, itemWidth: CGFloat, itemHeight: CGFloat) -> Int? {
        let cellHeight = itemHeight + 24
        let totalCellWidth = itemWidth + spacing
        let totalCellHeight = cellHeight + verticalSpacing

        // Adjust position relative to grid
        let adjustedX = position.x - horizontalPadding
        let adjustedY = position.y - topPadding

        guard adjustedX >= 0, adjustedY >= 0 else { return nil }

        let col = Int(adjustedX / totalCellWidth)
        let row = Int(adjustedY / totalCellHeight)

        guard col >= 0, col < columns else { return nil }

        let index = row * columns + col
        guard index >= 0, index < reorderedPages.count else { return nil }

        return index
    }

    // MARK: - Drag Handling

    private func startDrag(page: ScannedPage) {
        withAnimation(.easeOut(duration: 0.15)) {
            draggedPageId = page.id
            isDragging = true
            dragOffset = .zero
        }
    }

    private func handleDrag(translation: CGSize, itemWidth: CGFloat, itemHeight: CGFloat) {
        dragOffset = translation

        guard let draggedId = draggedPageId,
              let currentIndex = reorderedPages.firstIndex(where: { $0.id == draggedId }) else { return }

        // Calculate drag position including pickup offset
        let basePosition = itemPosition(for: currentIndex, itemWidth: itemWidth, itemHeight: itemHeight)
        let dragPosition = CGPoint(
            x: basePosition.x + translation.width + pickupOffset.width,
            y: basePosition.y + translation.height + pickupOffset.height
        )

        // Find target index
        if let targetIndex = indexAtPosition(dragPosition, itemWidth: itemWidth, itemHeight: itemHeight),
           targetIndex != currentIndex {
            // Perform reorder
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                reorderedPages.move(
                    fromOffsets: IndexSet(integer: currentIndex),
                    toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex
                )
            }
            // Adjust drag offset to account for position change
            let newPosition = itemPosition(for: targetIndex, itemWidth: itemWidth, itemHeight: itemHeight)
            let positionDelta = CGSize(
                width: basePosition.x - newPosition.x,
                height: basePosition.y - newPosition.y
            )
            dragOffset = CGSize(
                width: translation.width + positionDelta.width,
                height: translation.height + positionDelta.height
            )
        }
    }

    private func endDrag() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isDragging = false
            draggedPageId = nil
            dragOffset = .zero
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
                    // Actual thumbnail
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
