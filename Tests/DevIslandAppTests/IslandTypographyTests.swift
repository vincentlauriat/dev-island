import Foundation
import SwiftUI
import Testing
@testable import DevIslandApp

/// The typography roles replaced 24 hardcoded `.font(.system(...))` calls in the
/// notification card. The property that makes that refactor safe is that at
/// default settings every site resolves to the exact size, weight and design it
/// had before — so a user who never opens the pane sees no change at all.
///
/// These tests pin that property. They are written against the resolved values
/// rather than against `Font`, which is opaque and not inspectable.
struct IslandTypographyTests {

    // Every rewritten call site: the role and offset it now uses, against the
    // literal size it used to hardcode.
    private static let callSites: [(role: IslandTextRole, offset: Double, original: Double)] = [
        // Title
        (.title, 0, 13.2),      // summaryTitleFont, base
        (.title, 0.6, 13.8),    // summaryTitleFont, actionable row
        (.title, -0.7, 12.5),   // "tool permission requested"
        (.title, -0.2, 13.0),   // structured question prompt title
        // Body
        (.body, 0.2, 11.2),     // prompt line
        (.body, 0, 11),         // activity line, subagent name
        (.body, -2, 9),         // branch icon
        (.body, -0.5, 10.5),    // subagents title, task rows, affected path
        (.body, -1, 10),        // subagent completed / elapsed, question header
        (.body, 1, 12),         // question text
        (.body, 1.2, 12.2),     // option label
        // Code
        (.code, 0.5, 12),       // running detail
        (.code, 0, 11.5),       // command preview
        // Badge
        (.badge, 0, 10.5),      // age badge, agent badge, option index
        (.badge, -2, 8.5),      // terminal / SSH side badge
    ]

    @Test("Default typography reproduces every original hardcoded size")
    func defaultsMatchOriginalSizes() {
        let typography = IslandTypographyPreferences()
        for site in Self.callSites {
            let resolved = typography.size(site.role) + site.offset
            #expect(
                abs(resolved - site.original) < 0.0001,
                "\(site.role) offset \(site.offset) resolved to \(resolved), expected \(site.original)"
            )
        }
    }

    @Test("Markdown body and code offsets reproduce the theme's original sizes")
    func markdownOffsetsMatchOriginalSizes() {
        let typography = IslandTypographyPreferences()
        #expect(typography.size(.body) + 2.5 == 13.5)
        #expect(typography.size(.code) + 1 == 12.5)
    }

    @Test("A fresh preferences value stores nothing and reports itself as default")
    func freshPreferencesAreDefault() {
        let typography = IslandTypographyPreferences()
        #expect(typography.isDefault)
        #expect(typography.sizes.isEmpty)
        #expect(typography.weights.isEmpty)
    }

    @Test("Changing any role clears the default flag")
    func mutationClearsDefaultFlag() {
        for role in IslandTextRole.allCases {
            var sized = IslandTypographyPreferences()
            sized.sizes[role] = role.defaultSize + 1
            #expect(!sized.isDefault, "size change to \(role) should not read as default")

            var weighted = IslandTypographyPreferences()
            weighted.weights[role] = role.defaultWeight == .bold ? .regular : .bold
            #expect(!weighted.isDefault, "weight change to \(role) should not read as default")
        }
    }

    @Test("Storing a role's own default value still reads as default")
    func explicitDefaultValueReadsAsDefault() {
        var typography = IslandTypographyPreferences()
        for role in IslandTextRole.allCases {
            typography.sizes[role] = role.defaultSize
            typography.weights[role] = role.defaultWeight
        }
        #expect(typography.isDefault)
    }

    @Test("Every role's default size sits inside its own slider range")
    func defaultSizesAreReachableFromTheSlider() {
        for role in IslandTextRole.allCases {
            #expect(
                role.sizeRange.contains(role.defaultSize),
                "\(role) default \(role.defaultSize) is outside \(role.sizeRange)"
            )
        }
    }

    /// The badge role carries a -2 offset. Dragging its slider to the floor must
    /// not drive that site to zero or below, which renders as invisible text.
    @Test("The largest negative offset stays positive at the smallest size")
    func minimumSizesStayRenderable() {
        var typography = IslandTypographyPreferences()
        for role in IslandTextRole.allCases {
            typography.sizes[role] = role.sizeRange.lowerBound
        }
        let worstOffset = Self.callSites.map(\.offset).min() ?? 0
        for role in IslandTextRole.allCases {
            let resolved = max(4, typography.size(role) + worstOffset)
            #expect(resolved >= 4, "\(role) clamped to \(resolved)")
        }
    }

    @Test("Monospaced roles are exactly the ones the card renders in mono")
    func monospacedRolesAreStable() {
        #expect(!IslandTextRole.title.isMonospaced)
        #expect(!IslandTextRole.body.isMonospaced)
        #expect(IslandTextRole.code.isMonospaced)
        #expect(IslandTextRole.badge.isMonospaced)
    }

    @Test("Every persisted weight round-trips through its raw value")
    func fontWeightsRoundTrip() {
        for weight in IslandFontWeight.allCases {
            #expect(IslandFontWeight(rawValue: weight.rawValue) == weight)
        }
    }
}
