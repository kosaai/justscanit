# Just Scan It

A clean, fast document scanner app for iOS built with SwiftUI.

## Features

- **Auto Document Detection** - Automatically detects document edges using Vision framework
- **Auto & Manual Capture** - Choose between automatic capture when holding steady or manual shutter
- **Perspective Correction** - Automatically corrects skewed documents
- **Crop with Magnifier** - Precision cropping with magnifier loupe for accurate edge adjustment
- **Rotate & Enhance** - Rotate pages and apply auto-enhancement filters
- **Multi-page Documents** - Scan multiple pages into a single document
- **Reorder Pages** - Drag and drop to reorder pages within a document
- **Export Options** - Save as PDF or individual images
- **Share** - Share documents via iOS share sheet

## Screenshots

The app features a mint green accent color (#60D1AB) throughout the UI.

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Building

1. Clone the repository
2. Open `ScannerApp.xcodeproj` in Xcode
3. Select your target device or simulator
4. Build and run (⌘R)

## Project Structure

```
ScannerApp/
├── ScannerApp.swift          # App entry point
├── ContentView.swift         # Main navigation controller
├── AppColors.swift           # App-wide color definitions
├── Info.plist                # App configuration
├── Models/
│   └── ScannedDocument.swift # Document and page data models
├── Views/
│   ├── HomeView.swift        # Document list screen
│   ├── ScannerView.swift     # Camera scanning interface
│   ├── DocumentDetailView.swift # Document viewer with carousel
│   ├── CropView.swift        # Crop editor with magnifier
│   ├── ReorderPagesView.swift # Page reordering grid
│   ├── PageAdjustmentToolbar.swift # Edit actions toolbar
│   ├── SettingsSheetView.swift # Scanner settings
│   └── ...
└── Services/
    ├── CameraManager.swift   # Camera session management
    ├── ImageProcessor.swift  # Image processing & filters
    ├── DocumentStorage.swift # Document persistence
    ├── PDFGenerator.swift    # PDF export
    └── ScannerSettings.swift # User preferences
```

## Privacy

- Camera access is required for scanning documents
- Photo library access is optional for saving images
- All documents are stored locally on device
- No data is collected or transmitted

## License

MIT License
