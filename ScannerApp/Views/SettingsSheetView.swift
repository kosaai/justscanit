import SwiftUI

struct SettingsSheetView: View {
    @ObservedObject var settings: ScannerSettings
    let onLightModeChange: (LightMode) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            // Title
            HStack {
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // Settings sections
            VStack(spacing: 16) {
                // Light setting
                SettingRow(
                    icon: lightIconName,
                    title: "Light",
                    options: LightMode.allCases.map { $0.rawValue },
                    selected: settings.lightModeValue.rawValue
                ) { selected in
                    if let mode = LightMode(rawValue: selected) {
                        settings.lightModeValue = mode
                        onLightModeChange(mode)
                    }
                }

                // Capture mode setting
                SettingRow(
                    icon: "camera.viewfinder",
                    title: "Capture",
                    options: CaptureMode.allCases.map { $0.rawValue },
                    selected: settings.captureModeValue.rawValue
                ) { selected in
                    if let mode = CaptureMode(rawValue: selected) {
                        settings.captureModeValue = mode
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color(.systemBackground))
    }

    private var lightIconName: String {
        switch settings.lightModeValue {
        case .auto: return "bolt.badge.automatic"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash"
        }
    }
}

// MARK: - Setting Row

struct SettingRow: View {
    let icon: String
    let title: String
    let options: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Label
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
            }

            // Options
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        Text(option)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selected == option ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selected == option ? Color.blue : Color(.systemGray5))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
