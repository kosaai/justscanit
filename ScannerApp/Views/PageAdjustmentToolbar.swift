import SwiftUI
import UIKit

struct PageAdjustmentToolbar: View {
    let isEnhanced: Bool
    let onDelete: () -> Void
    let onRotate: () -> Void
    let onCrop: () -> Void
    let onRestoreEnhance: () -> Void

    private let tealColor = Color(red: 0.0, green: 0.6, blue: 0.65)

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar content
            HStack(spacing: 0) {
                AdjustmentButton(
                    icon: "trash",
                    label: "Delete",
                    action: onDelete
                )

                Spacer()

                AdjustmentButton(
                    icon: "rotate.right",
                    label: "Rotate",
                    action: onRotate
                )

                Spacer()

                AdjustmentButton(
                    icon: "crop",
                    label: "Crop",
                    action: onCrop
                )

                Spacer()

                AdjustmentButton(
                    icon: isEnhanced ? "doc.text" : "doc.text.fill.viewfinder",
                    label: isEnhanced ? "Restore" : "Enhance",
                    action: onRestoreEnhance
                )
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(tealColor)
        .clipShape(
            RoundedCorner(radius: 20, corners: [.topLeft, .topRight])
        )
    }
}

struct AdjustmentButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(Color(red: 0.0, green: 0.5, blue: 0.55))
                }

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
        }
    }
}

// Helper for rounded corners on specific sides
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
