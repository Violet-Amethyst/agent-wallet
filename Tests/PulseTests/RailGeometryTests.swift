import Foundation
import Testing
@testable import Pulse

/// Every ring the rail draws has to be reachable.
///
/// The panel window gates every press on its grab area, which it measures
/// from the rail's length. When that length was counted in accounts while the
/// view drew it in slots, the two differed by one the moment a provider was
/// split — and the shortfall lands at the far end, so the *last* ring was the
/// one that stopped responding.
///
/// Two halves, because the first alone is not enough: the count is what
/// shipped broken, and geometry asserted on two hand-built numbers cannot
/// catch a wrong count — the numbers *are* the bug. So `shownSlotCount` is
/// called here for real, and the rest pins the geometry that makes agreeing on
/// it sufficient, at every edge and both dock states.
extension PanelGlobalsSuite {
    @Suite("Rail geometry")
    struct RailGeometryTests {
    private static let edges: [PanelEdge] = [.left, .right, .top]
    /// One, a handful, and a rail longer than any real one.
    private static let counts = [1, 2, 3, 7, 15, 16]

    /// Runs `body` once per end style.
    ///
    /// `AppSettings.usesRoundEnds` picks between two different rails: softened
    /// ends take a written `verticalPadding` of 46, round ones derive 54 from
    /// the end's own circle. The invariants below have to hold for both, and
    /// only one of them is the default — so without this the other ships
    /// untested. The flag is a global on `PanelMetrics`, which is why the
    /// suite is serialized and why the original is put back.
    private func underEachEndStyle(_ body: (String) -> Void) {
        let original = PanelMetrics.usesRoundEnds
        defer { PanelMetrics.useRoundEnds(original) }

        for round in [false, true] {
            PanelMetrics.useRoundEnds(round)
            body(round ? "round ends" : "softened ends")
        }
    }

    /// Where the rail's own hit area sits, for a rail of `count` rings.
    private func rail(_ count: Int, _ edge: PanelEdge, docked: Bool) -> CGRect {
        PanelHitArea.rail(
            edge: edge,
            railSize: DockLayout.size(for: count, on: edge.axis, docked: docked),
            railTop: 0,
            railLeading: 0
        )
    }

    /// The centre of ring `index`, by the same sum the hit test uses.
    private func ringCentre(_ index: Int, in rail: CGRect, _ edge: PanelEdge, docked: Bool) -> CGPoint {
        let along = DockLayout.firstRingAlong(docked: docked, on: edge.axis)
            + CGFloat(index) * DockLayout.ringStep(on: edge.axis)
        let across = DockLayout.ringCentreAcross(on: edge.axis)
        return edge.isVertical
            ? CGPoint(x: rail.minX + across, y: rail.minY + along)
            : CGPoint(x: rail.minX + along, y: rail.minY + across)
    }

    @MainActor
    @Test("Every ring's centre lies inside the rail it is drawn on")
    func everyRingCentreIsInsideTheRail() {
        underEachEndStyle { style in
            for edge in Self.edges {
                for docked in [true, false] {
                    for count in Self.counts {
                        let area = rail(count, edge, docked: docked)

                        for index in 0..<count {
                            let centre = ringCentre(index, in: area, edge, docked: docked)
                            #expect(
                                area.contains(centre),
                                "ring \(index) of \(count), \(edge) edge, docked \(docked), \(style)"
                            )
                        }
                    }
                }
            }
        }
    }

    /// The bug in the flesh: the *whole* ring has to be reachable, not just
    /// its centre. At Loose spacing the old undersized rail left only the top
    /// 4pt of the last ring live, which reads as a ring that ignores clicks
    /// rather than as one that is half outside its own hit area.
    @MainActor
    @Test("The last ring is wholly inside the rail, at every scale")
    func theLastRingIsNotClippedByTheRail() {
        let radius = DockLayout.ringDiameter / 2

        underEachEndStyle { style in
            for edge in Self.edges {
                for docked in [true, false] {
                    for count in Self.counts {
                        let area = rail(count, edge, docked: docked)
                        let centre = ringCentre(count - 1, in: area, edge, docked: docked)
                        let ring = CGRect(
                            x: centre.x - radius, y: centre.y - radius,
                            width: radius * 2, height: radius * 2
                        )

                        #expect(
                            area.contains(ring),
                            "last of \(count) rings, \(edge) edge, docked \(docked), \(style): \(ring) escapes \(area)"
                        )
                    }
                }
            }
        }
    }

    /// The two rules `DockBerthShape` is drawn against, for both styles.
    ///
    /// The corner and the flare share the rail's top and bottom edges, so
    /// `cornerRadius + flareWidth` may not exceed the width or the body's flat
    /// edge runs backwards and the outline folds in on itself. And the flare
    /// lives inside the bounding rect, so padding shorter than it would lay
    /// the first ring outside the shape and clip it. Neither is visible in a
    /// hit test, which is what the tests above check.
    @MainActor
    @Test("The berth outline cannot fold or clip, whichever ends are drawn")
    func theBerthOutlineHoldsItsConstraints() {
        underEachEndStyle { style in
            #expect(
                DockLayout.cornerRadius + DockLayout.flareWidth <= DockLayout.width,
                "\(style): corner and flare overrun the rail's width"
            )
            #expect(
                DockLayout.verticalPadding >= DockLayout.flareHeight,
                "\(style): the first ring is laid out inside the flare"
            )
        }
    }

    /// The count itself — which is what actually shipped broken.
    ///
    /// The window measured its rects from `shownAccounts.count` while the view
    /// drew `entries.count`; with a split account those differ by one. Asserting
    /// geometry on two hand-built numbers cannot catch that, because the numbers
    /// are the bug. This calls the function the window really uses, with a
    /// reading that really splits, and fails against `shownAccounts.count`.
    @MainActor
    @Test("The window counts rings, not accounts")
    func theWindowCountsRingsNotAccounts() {
        let antigravity = AccountKey(.antigravity)
        let settings = AppSettings(
            enabledAccounts: [antigravity.id],
            splitAccounts: [antigravity.id]
        )

        let split = ProviderUsage(
            account: antigravity,
            windows: [
                UsageWindow(id: "g5", kind: .fiveHour, scope: "Gemini", usedFraction: 0.4, windowSeconds: 18_000, resetsAt: nil),
                UsageWindow(id: "t5", kind: .fiveHour, scope: "Third-party", usedFraction: 0.2, windowSeconds: 18_000, resetsAt: nil),
            ],
            observedAt: Date(),
            state: .live,
            plan: nil,
            creditBalance: nil
        )

        #expect(settings.shownAccounts == [antigravity])
        // One account, two rings. `shownAccounts.count` would answer 1.
        #expect(FloatingPanelController.shownSlotCount(settings, usage: { _ in split }) == 2)

        // And the rail the window sizes from is a ring longer for it.
        let short = DockLayout.size(for: 1, on: .vertical, docked: true)
        let real = DockLayout.size(for: 2, on: .vertical, docked: true)
        #expect(real.height > short.height)
    }

    /// The same account before its first reading lands: nothing to split by, so
    /// the window counts one — and must go back to two when the reading arrives,
    /// which is what `PanelPlacement.railLengthChanged()` exists to notice.
    @MainActor
    @Test("The count follows the reading, not the settings")
    func theCountFollowsTheReading() {
        let antigravity = AccountKey(.antigravity)
        let settings = AppSettings(
            enabledAccounts: [antigravity.id],
            splitAccounts: [antigravity.id]
        )

        let loading = ProviderUsage.unavailable(antigravity, reason: .loading)
        #expect(FloatingPanelController.shownSlotCount(settings, usage: { _ in loading }) == 1)
    }

    @MainActor
    @Test("Every ring answers the hit test as itself")
    func everyRingHitTestsToItsOwnSlot() {
        let slots = (0..<5).map { RailSlot(AccountKey(Provider.allCases[$0])) }

        for edge in Self.edges {
            for docked in [true, false] {
                let area = rail(slots.count, edge, docked: docked)

                for (index, slot) in slots.enumerated() {
                    let centre = ringCentre(index, in: area, edge, docked: docked)
                    let hit = PanelHitArea.slot(
                        at: centre, edge: edge, slots: slots,
                        railTop: 0, railLeading: 0, docked: docked
                    )

                    #expect(hit == slot, "ring \(index), \(edge) edge, docked \(docked)")
                }
            }
        }
    }

    /// The window's size is whole points at every scale and edge.
    ///
    /// AppKit rounds the frame it is given; SwiftUI draws the rail against the
    /// rounded one while hit tests use this. A fractional width left the last
    /// half point at the screen edge drawn but dead, and a pointer pushed
    /// against a docked rail closed it.
    @Test("The panel's size is whole points", arguments: edges)
    func panelSizeIsIntegral(edge: PanelEdge) {
        let original = PanelSize.allCases.first { $0.scale == PanelMetrics.scale } ?? .default
        defer { PanelMetrics.use(original) }

        underEachEndStyle { style in
            for size in PanelSize.allCases {
                PanelMetrics.use(size)
                let panel = FloatingPanelController.Layout.size(for: edge)
                #expect(panel.width == panel.width.rounded(), "\(edge) \(size) \(style): width \(panel.width)")
                #expect(panel.height == panel.height.rounded(), "\(edge) \(size) \(style): height \(panel.height)")
            }
        }
    }
}

/// Nothing may move the panel while it is under a held mouse button.
///
/// The grab offset is measured at mouse-down, so a re-place between the press
/// and the first movement does not slide the panel — it makes it *jump* by
/// that much on the frame the pointer first travels, out from under the hand
/// carrying it.
@Suite("Holding the panel")
struct PanelHoldTests {
    private func placement(pressed: Bool = false, dragging: Bool = false) -> (PanelPlacement, () -> Int) {
        let placement = PanelPlacement()
        placement.isPressed = pressed
        placement.isDragging = dragging

        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        placement.onChange = { counter.value += 1 }
        return (placement, { counter.value })
    }

    @Test("A rail-length change re-places the panel when nothing is holding it")
    func anIdlePanelIsRePlaced() {
        let (placement, calls) = placement()
        placement.railLengthChanged()

        #expect(calls() == 1)
    }

    /// The gap this closes: `isDragging` is only set on the first *movement*.
    @Test("A held panel is not re-placed, even before it has moved")
    func aHeldPanelIsLeftAlone() {
        let (placement, calls) = placement(pressed: true)
        placement.railLengthChanged()

        #expect(calls() == 0)
    }

    @Test("A panel being dragged is not re-placed")
    func aDraggedPanelIsLeftAlone() {
        let (placement, calls) = placement(pressed: true, dragging: true)
        placement.railLengthChanged()

        #expect(calls() == 0)
    }

    @Test("Letting go lets it be re-placed again")
    func releasingRestoresIt() {
        let (placement, calls) = placement(pressed: true, dragging: true)
        placement.railLengthChanged()
        #expect(calls() == 0)

        placement.isDragging = false
        placement.isPressed = false
        placement.railLengthChanged()

        #expect(calls() == 1)
    }
}

/// The rail's offsets are measured from the panel's own edges, so they are
/// only meaningful against the frame the window actually has.
///
/// `layout(in:topEdge:panel:rail:)` returns a frame and offsets relative to
/// it, but the frame is a **request**: the panel is as tall as a rail with
/// every account switched on — 1133pt — which is taller than the usable area
/// of a laptop display, and AppKit's `constrainFrameRect` pulls such a window
/// down so its top stays under the menu bar. The offsets were then expressed
/// against a position the window never had, and the drag round-tripped that
/// difference through `ratios(forRailAt:)` — 72pt of it, once, on the first
/// frame the pointer moved.
@Suite("Rail offsets against the real frame")
struct RailOffsetTests {
    /// A 16" laptop: 1169pt tall, 35pt of menu bar, 72pt of Dock.
    private let visible = CGRect(x: 0, y: 72, width: 1800, height: 1058)
    private let panel = CGSize(width: 280.44, height: 1133.24)
    private let rail = CGSize(width: 52.48, height: 444.44)

    @Test("Offsets put the rail where the layout meant it to be")
    func offsetsRoundTripAgainstTheGrantedFrame() {
        let placement = PanelPlacement(dock: .floating(.vertical), horizontalRatio: 0.8, verticalRatio: 0.44)
        let layout = placement.layout(in: visible, topEdge: 1134, panel: panel, rail: rail)

        // Granted as asked: the rail's top lands exactly where layout put it.
        let asGranted = PanelPlacement.offsets(
            forRailTopLeft: layout.railOrigin, in: layout.frame, rail: rail
        )
        #expect(abs(layout.frame.maxY - asGranted.top - layout.railOrigin.y) < 0.01)
    }

    /// The refusal this suite exists for, with the numbers the probe recorded.
    @Test("A frame the window was refused does not move the rail")
    func aRefusedFrameDoesNotMoveTheRail() {
        let placement = PanelPlacement(dock: .floating(.vertical), horizontalRatio: 0.8, verticalRatio: 0.44)
        let layout = placement.layout(in: visible, topEdge: 1134, panel: panel, rail: rail)

        // What AppKit actually grants: the top pinned under the menu bar.
        let granted = CGRect(
            x: layout.frame.minX, y: 0,
            width: 281, height: 1134
        )
        #expect(granted.origin.y != layout.frame.origin.y)

        // Measured against the frame the window has, the rail's top is still
        // the screen position the layout chose.
        let right = PanelPlacement.offsets(
            forRailTopLeft: layout.railOrigin, in: granted, rail: rail
        )
        #expect(abs(granted.maxY - right.top - layout.railOrigin.y) < 0.01)

        // Measured against the frame that was *asked* for — which is what the
        // struct used to hand out, and what shipped — the rail lands exactly
        // the refused distance away. Not a rounding error: 72pt.
        let wrong = PanelPlacement.offsets(
            forRailTopLeft: layout.railOrigin, in: layout.frame, rail: rail
        )
        #expect(abs(granted.maxY - wrong.top - layout.railOrigin.y) > 70)
    }

    @Test("The rail is never asked to sit outside the window")
    func offsetsAreClampedToTheWindow() {
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 200)
        let offsets = PanelPlacement.offsets(
            forRailTopLeft: CGPoint(x: -500, y: 5_000), in: tiny, rail: rail
        )

        #expect(offsets.top >= 0)
        #expect(offsets.top <= max(tiny.height - rail.height, 0))
        #expect(offsets.leading >= 0)
        #expect(offsets.leading <= max(tiny.width - rail.width, 0))
    }

    /// The two proportions of a rail lying free across, and the top dock's,
    /// which neither may change.
    @Suite("Free lying rail proportions", .serialized)
    struct FreeLyingRailProportionTests {
        @MainActor
        @Test("Figures under: closer rings and more room above and below; beside: the upright rail's thickness; docked: untouched")
        func proportions() {
            let labels = PanelMetrics.topRailShowsPercentages
            let beside = PanelMetrics.freeAcrossFiguresBeside
            let dual = PanelMetrics.usesDualTrack
            defer {
                PanelMetrics.showTopPercentages(labels)
                PanelMetrics.putFreeAcrossFiguresBeside(beside)
                PanelMetrics.useDualTrack(dual)
            }
            PanelMetrics.useDualTrack(false)
            PanelMetrics.showTopPercentages(true)

            PanelMetrics.putFreeAcrossFiguresBeside(false)
            // Where the hit test puts a ring is where the drawing does: the
            // stacked item centred in the free rail's own thickness, behind its
            // own padding — not the top dock's.
            if !DockLayout.labelLeads {
                #expect(DockLayout.ringCentreAcross(on: .horizontal, docked: false)
                    == DockLayout.crossPadding(on: .horizontal, docked: false) + DockLayout.ringDiameter / 2)
            }
            let docked = DockLayout.thickness(on: .horizontal, docked: true)
            let dockedStep = DockLayout.ringStep(on: .horizontal, docked: true)
            #expect(DockLayout.thickness(on: .horizontal, docked: false) == docked + 8 * PanelMetrics.scale)
            #expect(DockLayout.ringStep(on: .horizontal, docked: false) == dockedStep - 10 * PanelMetrics.scale * PanelMetrics.spacing)

            PanelMetrics.putFreeAcrossFiguresBeside(true)
            #expect(DockLayout.thickness(on: .horizontal, docked: false) == DockLayout.thickness(on: .vertical))
            // Beside means right of the ring, even with figures set above
            // (issue #73): the ring leads its item.
            let above = PanelMetrics.labelAboveRing
            PanelMetrics.putLabelAboveRing(true)
            #expect(DockLayout.firstRingAlong(docked: false, on: .horizontal)
                == DockLayout.endPadding(docked: false) + DockLayout.ringDiameter / 2)
            PanelMetrics.putLabelAboveRing(above)
            // The time arc moves a figure 5pt further from its ring.
            let clock = PanelMetrics.showsWindowClock
            PanelMetrics.showWindowClock(false)
            let plain = DockLayout.ringToTextSpacing
            PanelMetrics.showWindowClock(true)
            #expect(DockLayout.ringToTextSpacing == plain + 5 * PanelMetrics.scale)
            PanelMetrics.showWindowClock(clock)
            #expect(DockLayout.thickness(on: .horizontal, docked: true) == docked)
            #expect(DockLayout.ringStep(on: .horizontal, docked: true) == dockedStep)
            // The window is budgeted for the longer and the thicker of the rails.
            #expect(DockLayout.maximumLength(on: .horizontal, capacity: 7)
                == DockLayout.length(for: 7, on: .horizontal, docked: false))
        }
    }

    @Suite("Dual-track Olympic rail geometry")
    struct DualTrackOlympicRailGeometryTests {
    private struct TestSlot: Identifiable {
        let id: String
        let isMoney: Bool
    }

    private let quotaSlots = [
        TestSlot(id: "antigravity", isMoney: false),
        TestSlot(id: "claudeCode", isMoney: false),
        TestSlot(id: "copilot", isMoney: false),
        TestSlot(id: "cursor", isMoney: false),
        TestSlot(id: "qoder", isMoney: false)
    ]

    private let moneySlots = [
        TestSlot(id: "deepSeek", isMoney: true),
        TestSlot(id: "openAI", isMoney: true),
        TestSlot(id: "xai", isMoney: true)
    ]

    private var allSlots: [TestSlot] {
        quotaSlots + moneySlots
    }

    @Test("Left rail positions quota on left and money on right staggered at midlines")
    func leftRailDualTrackPositions() {
        let originalEnds = PanelMetrics.usesRoundEnds
        PanelMetrics.useRoundEnds(false)
        PanelMetrics.useDualTrack(true)
        defer {
            PanelMetrics.useRoundEnds(originalEnds)
            PanelMetrics.useDualTrack(false)
        }

        let edge = PanelEdge.left
        let docked = true
        let size = DockLayout.size(quotaCount: quotaSlots.count, moneyCount: moneySlots.count, on: edge.axis, docked: docked)
        #expect(size.width == 120 * PanelMetrics.scale)

        let railRect = PanelHitArea.rail(edge: edge, railSize: size, railTop: 0, railLeading: 0)
        let geos = DockLayout.slotGeometries(
            for: allSlots,
            isMoney: { $0.isMoney },
            edge: edge,
            docked: docked
        )

        let firstAlong = DockLayout.firstRingAlong(docked: docked, on: edge.axis)
        let step = DockLayout.ringStep(on: edge.axis, isDual: true)
        let radius = DockLayout.ringDiameter / 2

        // Verify quota slots: column 1 (left)
        for (i, slot) in quotaSlots.enumerated() {
            let geo = geos[slot.id]!
            #expect(!geo.isMoney)
            #expect(abs(geo.across - 34 * PanelMetrics.scale) < 0.01)
            #expect(abs(geo.along - (firstAlong + CGFloat(i) * step)) < 0.01)

            let ringBox = CGRect(
                x: geo.ringCentre.x - radius,
                y: geo.ringCentre.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            #expect(railRect.contains(ringBox))
        }

        // Verify money slots: column 2 (right), staggered at midlines
        for (j, slot) in moneySlots.enumerated() {
            let geo = geos[slot.id]!
            #expect(geo.isMoney)
            #expect(abs(geo.across - 86 * PanelMetrics.scale) < 0.01)
            #expect(abs(geo.along - (firstAlong + (CGFloat(j) + 0.5) * step)) < 0.01)

            let ringBox = CGRect(
                x: geo.ringCentre.x - radius,
                y: geo.ringCentre.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            #expect(railRect.contains(ringBox))
        }
    }

    @Test("Right rail positions quota on left and money on right")
    func rightRailDualTrackPositions() {
        PanelMetrics.useDualTrack(true)
        defer { PanelMetrics.useDualTrack(false) }

        let edge = PanelEdge.right
        let docked = true
        let size = DockLayout.size(quotaCount: quotaSlots.count, moneyCount: moneySlots.count, on: edge.axis, docked: docked)
        #expect(size.width == 120 * PanelMetrics.scale)

        let geos = DockLayout.slotGeometries(
            for: allSlots,
            isMoney: { $0.isMoney },
            edge: edge,
            docked: docked
        )

        // Quota rings are on the left (across = 34)
        for slot in quotaSlots {
            let geo = geos[slot.id]!
            #expect(abs(geo.across - 34 * PanelMetrics.scale) < 0.01)
        }

        // Money rings are on the right (across = 86)
        for slot in moneySlots {
            let geo = geos[slot.id]!
            #expect(abs(geo.across - 86 * PanelMetrics.scale) < 0.01)
        }
    }

    @Test("Top rail positions money on top row and quota on bottom row")
    func topRailDualTrackPositions() {
        PanelMetrics.useDualTrack(true)
        defer { PanelMetrics.useDualTrack(false) }

        let edge = PanelEdge.top
        let docked = true
        let size = DockLayout.size(quotaCount: quotaSlots.count, moneyCount: moneySlots.count, on: edge.axis, docked: docked)
        let railRect = PanelHitArea.rail(edge: edge, railSize: size, railTop: 0, railLeading: 0)

        let geos = DockLayout.slotGeometries(
            for: allSlots,
            isMoney: { $0.isMoney },
            edge: edge,
            docked: docked
        )

        let firstAlong = DockLayout.firstRingAlong(docked: docked, on: edge.axis)
        let step = DockLayout.ringStep(on: edge.axis, isDual: true)
        let radius = DockLayout.ringDiameter / 2

        // Money rings on top row (Row 1, across = 34)
        for (j, slot) in moneySlots.enumerated() {
            let geo = geos[slot.id]!
            #expect(abs(geo.across - 34 * PanelMetrics.scale) < 0.01)
            #expect(abs(geo.along - (firstAlong + (CGFloat(j) + 0.5) * step)) < 0.01)

            let ringBox = CGRect(
                x: geo.ringCentre.x - radius,
                y: geo.ringCentre.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            #expect(railRect.contains(ringBox))
        }

        // Quota rings on bottom row (Row 2, across = 86)
        for (i, slot) in quotaSlots.enumerated() {
            let geo = geos[slot.id]!
            #expect(abs(geo.across - 86 * PanelMetrics.scale) < 0.01)
            #expect(abs(geo.along - (firstAlong + CGFloat(i) * step)) < 0.01)

            let ringBox = CGRect(
                x: geo.ringCentre.x - radius,
                y: geo.ringCentre.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            #expect(railRect.contains(ringBox))
        }
    }

    @Test("PanelHitArea slot hits exact circle in dual track")
    func hitTestingInDualTrack() {
        PanelMetrics.useDualTrack(true)
        defer { PanelMetrics.useDualTrack(false) }

        let railSlots = allSlots.map { RailSlot(AccountKey(Provider(rawValue: $0.id) ?? .antigravity)) }
        let edge = PanelEdge.left
        let docked = true
        let size = DockLayout.size(quotaCount: quotaSlots.count, moneyCount: moneySlots.count, on: edge.axis, docked: docked)
        let rail = PanelHitArea.rail(edge: edge, railSize: size, railTop: 0, railLeading: 0)

        let isMoney: (RailSlot) -> Bool = { slot in
            let id = slot.id
            return id == "deepSeek" || id == "openAI" || id == "xai"
        }

        let geos = DockLayout.slotGeometries(
            for: railSlots,
            isMoney: isMoney,
            edge: edge,
            docked: docked
        )

        for slot in railSlots {
            let geo = geos[slot.id]!
            let clickPoint = CGPoint(x: rail.minX + geo.ringCentre.x, y: rail.minY + geo.ringCentre.y)
            let hit = PanelHitArea.slot(
                at: clickPoint,
                edge: edge,
                slots: railSlots,
                isMoney: isMoney,
                railTop: 0,
                railLeading: 0,
                docked: docked
            )
            #expect(hit?.id == slot.id)
        }
    }
}
}
}

