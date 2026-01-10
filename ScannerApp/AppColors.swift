import SwiftUI

/// App-wide color definitions
enum AppColors {
    /// Primary accent color #60D1AB - mint/teal green
    static let accent = Color(red: 96/255, green: 209/255, blue: 171/255)

    /// Darker variant for icons on accent background
    static let accentDark = Color(red: 60/255, green: 160/255, blue: 130/255)

    /// Light variant for subtle backgrounds
    static let accentLight = Color(red: 96/255, green: 209/255, blue: 171/255).opacity(0.2)
}
