import Foundation

/// One desktop panel: a titled, resizable container holding its own items.
///
/// Unlike Desktop Bins, a bin here owns its contents outright rather than
/// arranging Finder's desktop icons, so its item order is explicit rather
/// than inferred from icon positions on screen.
struct Bin: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var colorHex: String
    var isCollapsed: Bool
    var items: [BinItem]

    /// Stable identifier of the display this bin lives on, plus its position
    /// relative to that display's origin, so bins stay on the right monitor
    /// when displays are attached, detached or rearranged.
    var displayUUID: String?
    var relativeX: Double?
    var relativeY: Double?

    init(
        id: UUID = UUID(),
        title: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        colorHex: String = "3B82F6",
        isCollapsed: Bool = false,
        items: [BinItem] = [],
        displayUUID: String? = nil,
        relativeX: Double? = nil,
        relativeY: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.colorHex = colorHex
        self.isCollapsed = isCollapsed
        self.items = items
        self.displayUUID = displayUUID
        self.relativeX = relativeX
        self.relativeY = relativeY
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        isCollapsed = try c.decode(Bool.self, forKey: .isCollapsed)
        items = try c.decodeIfPresent([BinItem].self, forKey: .items) ?? []
        displayUUID = try c.decodeIfPresent(String.self, forKey: .displayUUID)
        relativeX = try c.decodeIfPresent(Double.self, forKey: .relativeX)
        relativeY = try c.decodeIfPresent(Double.self, forKey: .relativeY)
    }
}
