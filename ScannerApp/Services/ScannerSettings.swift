import SwiftUI

class ScannerSettings: ObservableObject {
    static let shared = ScannerSettings()

    @AppStorage("lightMode") var lightMode: String = LightMode.off.rawValue
    @AppStorage("captureMode") var captureMode: String = CaptureMode.auto.rawValue

    private init() {}

    var lightModeValue: LightMode {
        get { LightMode(rawValue: lightMode) ?? .off }
        set { lightMode = newValue.rawValue }
    }

    var captureModeValue: CaptureMode {
        get { CaptureMode(rawValue: captureMode) ?? .auto }
        set { captureMode = newValue.rawValue }
    }
}
