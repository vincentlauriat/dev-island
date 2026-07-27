import SwiftUI

/// Typography of the notification card, expressed as four **text roles** rather
/// than one setting per event type.
///
/// The card that renders a permission request, a question and a completion is a
/// single component: of its 18 font calls only 3 are specific to the event type,
/// and the message body itself goes through MarkdownUI, which uses no `.font()`
/// at all. Tuning "the font of the completion card" would therefore have moved
/// almost nothing on screen, and three cards in one list rendering in three
/// typefaces reads as a bug rather than a preference. Roles cut across the three
/// types instead, so a change to `.body` reaches every card at once.
///
/// Only size and weight are configurable, always over the system font. A family
/// picker was considered and rejected: the app ships English, French and two
/// Chinese localizations, and a Latin-only face silently falls back for CJK text,
/// producing a card where half the glyphs come from another font.
enum IslandTextRole: String, CaseIterable, Identifiable, Sendable {
    /// Card headline — the session title and the "permission requested" banner.
    case title
    /// Prose: activity lines, prompts, paths, subagent and task rows.
    case body
    /// Commands and code, monospaced.
    case code
    /// Capsules and timestamps: agent name, terminal, SSH, age.
    case badge

    var id: String { rawValue }

    /// Size used when the user has not moved anything. These reproduce the
    /// hardcoded values the card shipped with, so a fresh install looks
    /// identical to one from before this setting existed.
    var defaultSize: Double {
        switch self {
        case .title: return 13.2
        case .body: return 11
        case .code: return 11.5
        case .badge: return 10.5
        }
    }

    var defaultWeight: IslandFontWeight {
        switch self {
        case .title: return .semibold
        case .body: return .medium
        case .code: return .semibold
        case .badge: return .medium
        }
    }

    /// Bounds for the settings slider. Deliberately narrow: the island is a
    /// fixed-width overlay, and past these values text either truncates or
    /// forces the panel to grow past what the notch can host.
    var sizeRange: ClosedRange<Double> {
        switch self {
        case .title: return 10...18
        case .body: return 9...16
        case .code: return 9...16
        case .badge: return 7...14
        }
    }

    /// `true` when the role is monospaced by nature. Code and badges are; the
    /// user cannot flip this, because a proportional agent badge breaks the
    /// column alignment the badge row relies on.
    var isMonospaced: Bool {
        switch self {
        case .title, .body: return false
        case .code, .badge: return true
        }
    }
}

/// `Font.Weight` is neither `RawRepresentable` nor `Codable`, so it cannot be
/// persisted directly. This mirrors the subset worth exposing — hairline and
/// black are omitted, they are unreadable at the sizes the island uses.
enum IslandFontWeight: String, CaseIterable, Identifiable, Sendable {
    case regular
    case medium
    case semibold
    case bold

    var id: String { rawValue }

    var fontWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

/// Per-role size and weight, persisted globally rather than per display profile:
/// the panel renders identically in the notch and on an external display, so
/// splitting typography per profile would ask the user the same question twice.
struct IslandTypographyPreferences: Equatable, Sendable {
    var sizes: [IslandTextRole: Double] = [:]
    var weights: [IslandTextRole: IslandFontWeight] = [:]

    func size(_ role: IslandTextRole) -> Double {
        sizes[role] ?? role.defaultSize
    }

    func weight(_ role: IslandTextRole) -> IslandFontWeight {
        weights[role] ?? role.defaultWeight
    }

    var isDefault: Bool {
        IslandTextRole.allCases.allSatisfy {
            size($0) == $0.defaultSize && weight($0) == $0.defaultWeight
        }
    }

    /// Resolve a role to a concrete font.
    ///
    /// - Parameters:
    ///   - sizeOffset: how far this particular site sits from its role's base
    ///     size. Call sites keep the deltas the design already had — the
    ///     terminal badge stays 2 pt below the agent badge, the running detail
    ///     stays 0.5 pt above the command preview — so moving a slider shifts
    ///     the whole role while preserving the relationships inside it.
    ///   - weight: overrides the role's weight for the rare site that
    ///     deliberately differs (a de-emphasised subagent description, an
    ///     emphasised agent badge).
    func font(
        _ role: IslandTextRole,
        sizeOffset: Double = 0,
        weight overrideWeight: IslandFontWeight? = nil
    ) -> Font {
        // Clamped so a slider at its minimum cannot drive an offset site to a
        // zero or negative point size, which renders as invisible text.
        let resolvedSize = max(4, size(role) + sizeOffset)
        let resolvedWeight = (overrideWeight ?? weight(role)).fontWeight
        if role.isMonospaced {
            return .system(size: resolvedSize, weight: resolvedWeight, design: .monospaced)
        }
        return .system(size: resolvedSize, weight: resolvedWeight)
    }
}
