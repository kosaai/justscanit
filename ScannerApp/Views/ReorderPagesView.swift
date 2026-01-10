import SwiftUI
import UIKit

struct ReorderPagesView: View {
    let pages: [ScannedPage]
    let onDone: ([ScannedPage]) -> Void
    let onCancel: () -> Void
    let onDeletePage: (UUID) -> Void

    @State private var reorderedPages: [ScannedPage] = []
    @State private var draggedPageId: UUID?
    @State private var currentDragPosition: CGPoint = .zero
    @State private var dragOffset: CGPoint = .zero  // Offset from finger to overlay center
    @State private var isDragging = false
    @State private var isLongPressActive = false  // Track when long press recognized
    @State private var showDeleteConfirm = false
    @State private var pageToDelete: ScannedPage?

    private let columns = 3
    private let spacing: CGFloat = 16
    private let horizontalPadding: CGFloat = 16
    private let verticalSpacing: CGFloat = 40
    private let topPadding: CGFloat = 20

    // Long press duration (100ms - quick response)
    private let longPressDuration: Double = 0.1

    // Scale when picked up (1.1x), pulsates to 1.15x
    private let pickedUpScale: CGFloat = 1.1
    private let pulseMaxScale: CGFloat = 1.15

    // Animation duration for grid reordering
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
                        gridContent(itemWidth: itemWidth, itemHeight: itemHeight, screenWidth: geometry.size.width)
                    }
                }

                // Dragged item overlay - shows when long press is active
                if isLongPressActive, let draggedId = draggedPageId,
                   let page = reorderedPages.first(where: { $0.id == draggedId }) {
                    DraggedPageOverlay(
                        page: page,
                        itemWidth: itemWidth,
                        itemHeight: itemHeight,
                        position: currentDragPosition,
                        baseScale: pickedUpScale,
                        maxScale: pulseMaxScale
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
                    reorderedPages.removeAll { $0.id == page.id }
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

    private func gridContent(itemWidth: CGFloat, itemHeight: CGFloat, screenWidth: CGFloat) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns),
            spacing: verticalSpacing
        ) {
            ForEach(Array(reorderedPages.enumerated()), id: \.element.id) { index, page in
                PageCellContainer(
                    page: page,
                    displayIndex: index + 1,
                    itemWidth: itemWidth,
                    itemHeight: itemHeight,
                    isBeingDragged: draggedPageId == page.id && isLongPressActive,
                    isAnyDragging: isLongPressActive,
                    onDelete: {
                        pageToDelete = page
                        showDeleteConfirm = true
                    },
                    onLongPressStart: {
                        startLongPress(page: page, itemWidth: itemWidth, itemHeight: itemHeight, index: index)
                    },
                    onDragChanged: { location, startLocation in
                        if draggedPageId == page.id {
                            handleDrag(location: location, startLocation: startLocation, itemWidth: itemWidth, itemHeight: itemHeight, index: index)
                        }
                    },
                    onDragEnded: {
                        endDrag()
                    }
                )
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, 40)
    }

    // MARK: - Position Calculation

    private func calculateItemWidth(screenWidth: CGFloat) -> CGFloat {
        let totalSpacing = spacing * CGFloat(columns - 1)
        let totalPadding = horizontalPadding * 2
        return (screenWidth - totalSpacing - totalPadding) / CGFloat(columns)
    }

    private func thumbnailCenter(for index: Int, itemWidth: CGFloat, itemHeight: CGFloat) -> CGPoint {
        let col = index % columns
        let row = index / columns
        let cellHeight = itemHeight + 32 // thumbnail + spacing + label
        let x = horizontalPadding + CGFloat(col) * (itemWidth + spacing) + itemWidth / 2
        // Center of thumbnail only, not the whole cell (which includes label below)
        let y = topPadding + CGFloat(row) * (cellHeight + verticalSpacing) + itemHeight / 2
        return CGPoint(x: x, y: y)
    }

    private func indexAtPosition(_ position: CGPoint, itemWidth: CGFloat, itemHeight: CGFloat) -> Int? {
        let cellHeight = itemHeight + 32
        let totalCellWidth = itemWidth + spacing
        let totalCellHeight = cellHeight + verticalSpacing

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

    private func startLongPress(page: ScannedPage, itemWidth: CGFloat, itemHeight: CGFloat, index: Int) {
        // Calculate the center position of the thumbnail for initial overlay position
        let center = thumbnailCenter(for: index, itemWidth: itemWidth, itemHeight: itemHeight)
        // Adjust for the top bar offset
        let adjustedCenter = CGPoint(x: center.x, y: center.y + 56)

        draggedPageId = page.id
        isLongPressActive = true
        isDragging = false  // Reset - will be set true on first drag event
        currentDragPosition = adjustedCenter
        dragOffset = .zero  // Will be calculated on first drag event
    }

    private func handleDrag(location: CGPoint, startLocation: CGPoint, itemWidth: CGFloat, itemHeight: CGFloat, index: Int) {
        // On first drag event, calculate the offset between finger and thumbnail center
        if !isDragging {
            isDragging = true
            // Offset = where finger started - where thumbnail center is
            // This offset stays constant throughout the drag
            dragOffset = CGPoint(
                x: startLocation.x - currentDragPosition.x,
                y: startLocation.y - currentDragPosition.y
            )
        }

        // Calculate overlay position: finger position minus the offset
        // This keeps the thumbnail at the same relative position under the finger
        let overlayPosition = CGPoint(
            x: location.x - dragOffset.x,
            y: location.y - dragOffset.y
        )
        currentDragPosition = overlayPosition

        // Use overlay position (not finger position) for reorder detection
        // This keeps overlay visuals and reorder logic in sync
        guard let draggedId = draggedPageId,
              let currentIndex = reorderedPages.firstIndex(where: { $0.id == draggedId }) else { return }

        if let targetIndex = indexAtPosition(overlayPosition, itemWidth: itemWidth, itemHeight: itemHeight),
           targetIndex != currentIndex {
            withAnimation(.easeInOut(duration: reorderAnimationDuration)) {
                reorderedPages.move(
                    fromOffsets: IndexSet(integer: currentIndex),
                    toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex
                )
            }
        }
    }

    private func endDrag() {
        isLongPressActive = false
        isDragging = false
        draggedPageId = nil
    }
}

// MARK: - Page Cell Container (handles gestures)

struct PageCellContainer: View {
    let page: ScannedPage
    let displayIndex: Int
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let isBeingDragged: Bool
    let isAnyDragging: Bool
    let onDelete: () -> Void
    let onLongPressStart: () -> Void
    let onDragChanged: (CGPoint, CGPoint) -> Void  // (location, startLocation)
    let onDragEnded: () -> Void

    @State private var hasStartedLongPress = false

    var body: some View {
        // The entire cell including the number - moves as one unit
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

                    if !isAnyDragging {
                        deleteButton
                    }
                }
            }
            .frame(width: itemWidth, height: itemHeight)

            // Page number - always shows, moves with the cell
            // Use transaction to disable animation on text changes to prevent duplicates
            Text("\(displayIndex)")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isBeingDragged ? .blue.opacity(0.5) : .blue)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.1)
                .onChanged { _ in
                    // Long press is being recognized
                }
                .onEnded { _ in
                    // Long press completed - start drag mode
                    hasStartedLongPress = true
                    onLongPressStart()
                }
                .simultaneously(with:
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            if hasStartedLongPress {
                                onDragChanged(value.location, value.startLocation)
                            }
                        }
                        .onEnded { _ in
                            if hasStartedLongPress {
                                hasStartedLongPress = false
                                onDragEnded()
                            }
                        }
                )
        )
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
    let baseScale: CGFloat
    let maxScale: CGFloat

    @State private var currentScale: CGFloat = 1.0
    @State private var isPulsing = false

    var body: some View {
        let imagePath = page.croppedImagePath ?? page.originalImagePath
        if let image = DocumentStorage.shared.loadImage(filename: imagePath) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: itemWidth, height: itemHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
                .scaleEffect(currentScale)
                .position(position)
                .onAppear {
                    // Immediately scale up
                    currentScale = baseScale
                    // Start pulsing after a brief moment
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isPulsing = true
                    }
                }
                .onChange(of: isPulsing) { pulsing in
                    if pulsing {
                        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                            currentScale = maxScale
                        }
                    }
                }
        }
    }
}
