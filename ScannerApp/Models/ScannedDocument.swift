import UIKit

// MARK: - Filter Mode

enum FilterMode: String, CaseIterable, Codable {
    case original = "Original"
    case autoColor = "Auto"
    case grayscale = "Grayscale"
}

// MARK: - Image Adjustments

struct ImageAdjustments: Codable, Equatable {
    var exposure: Float = 0      // -1 to 1
    var brightness: Float = 0    // -0.5 to 0.5
    var contrast: Float = 1      // 0.5 to 2

    static let `default` = ImageAdjustments()
}

// MARK: - Scanned Page

struct ScannedPage: Identifiable, Codable {
    let id: UUID
    let originalImagePath: String
    var croppedImagePath: String?
    var corners: [CGPoint]?
    var filterMode: FilterMode
    var adjustments: ImageAdjustments
    let capturedAt: Date

    init(
        id: UUID = UUID(),
        originalImagePath: String,
        croppedImagePath: String? = nil,
        corners: [CGPoint]? = nil,
        filterMode: FilterMode = .autoColor,
        adjustments: ImageAdjustments = .default,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.originalImagePath = originalImagePath
        self.croppedImagePath = croppedImagePath
        self.corners = corners
        self.filterMode = filterMode
        self.adjustments = adjustments
        self.capturedAt = capturedAt
    }
}

// MARK: - Scanned Document

struct ScannedDocument: Identifiable, Codable {
    let id: UUID
    var name: String
    var pages: [ScannedPage]
    let createdAt: Date
    var modifiedAt: Date
    var pdfPath: String?

    init(
        id: UUID = UUID(),
        name: String? = nil,
        pages: [ScannedPage] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        pdfPath: String? = nil
    ) {
        self.id = id
        self.name = name ?? ScannedDocument.generateDefaultName(date: createdAt)
        self.pages = pages
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.pdfPath = pdfPath
    }

    var pageCount: Int { pages.count }

    var thumbnailPath: String? {
        pages.first?.croppedImagePath ?? pages.first?.originalImagePath
    }

    static func generateDefaultName(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "Scan \(formatter.string(from: date))"
    }

    mutating func addPage(_ page: ScannedPage) {
        pages.append(page)
        modifiedAt = Date()
    }

    mutating func removePage(at index: Int) {
        guard index < pages.count else { return }
        pages.remove(at: index)
        modifiedAt = Date()
    }

    mutating func updatePage(at index: Int, with page: ScannedPage) {
        guard index < pages.count else { return }
        pages[index] = page
        modifiedAt = Date()
    }
}

// MARK: - CGPoint Codable

extension CGPoint: Codable {
    enum CodingKeys: String, CodingKey {
        case x, y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        self.init(x: x, y: y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
}
