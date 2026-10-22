import Foundation
import SwiftUI

public struct TaskCategory: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var icon: String

    public init(id: UUID = UUID(), name: String, colorHex: String, icon: String = "folder.fill") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
    }

    public var color: Color {
        Color(hex: colorHex)
    }

    public static let defaultCategories: [TaskCategory] = [
        TaskCategory(name: "Deep Work", colorHex: "#4F46E5", icon: "brain.head.profile"),
        TaskCategory(name: "Meetings", colorHex: "#0284C7", icon: "person.2.fill"),
        TaskCategory(name: "Study & Learning", colorHex: "#10B981", icon: "book.fill"),
        TaskCategory(name: "Admin & Email", colorHex: "#F59E0B", icon: "envelope.fill"),
        TaskCategory(name: "Wellness & Exercise", colorHex: "#EC4899", icon: "figure.run")
    ]
}

extension Color {
    public init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 79, 70, 229)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    public func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "#4F46E5" }
        let r = Float(components.redComponent)
        let g = Float(components.greenComponent)
        let b = Float(components.blueComponent)
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}
