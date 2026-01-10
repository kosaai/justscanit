import SwiftUI
import UIKit

struct PageAdjustmentToolbar: View {
    let isEnhanced: Bool
    let onDelete: () -> Void
    let onRotate: () -> Void
    let onCrop: () -> Void
    let onRestoreEnhance: () -> Void

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
            .padding(.top, 28)
            .padding(.bottom, 36)
        }
        .background(AppColors.accent)
        .clipShape(
            RoundedCorner(radius: 24, corners: [.topLeft, .topRight])
        )
    }
}

struct AdjustmentButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 62, height: 62)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(AppColors.accentDark)
                }

                Text(label)
                    .font(.system(size: 14, weight: .semibold))
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
