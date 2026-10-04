// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Builds the readings only when their observed inputs change. The child owns
/// pointer/card state and shares these entries across layout and hit testing.
struct FloatingUsagePanelView: View {
    let store: UsageStore
    let settings: AppSettings
    let placement: PanelPlacement
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    /// The clock arc moves to the minute even when quota refresh backs off.
    @State private var minute = Date()

    var body: some View {
        // Formatting reads the selected language through a plain function.
        let _ = settings.language
        FloatingUsagePanelContent(
            store: store,
            settings: settings,
            entries: entries,
            placement: placement,
            onSettings: onSettings,
            onQuit: onQuit
        )
        .task(id: settings.showsWindowClock) {
            guard settings.showsWindowClock else { return }
            while !Task.isCancelled {
                minute = Date()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Only the providers switched on in settings, so the rail shrinks when
    /// one is turned off.
    private var entries: [RailEntry] {
        RailSlot.rail(
            for: settings.shownAccounts,
            isSplit: settings.isSplit,
            groups: { RailSlot.modelGroups(of: store.usage(for: $0)) }
        ).map { slot in
            let usage = store.usage(for: slot.account)
            return entry(
                for: slot,
                usage: slot.group.map { Self.usage(usage, keeping: $0) } ?? usage
            )
        }
    }

    /// The same reading with only one group's limits in it, so every figure
    /// downstream — the ring, the card, the second ring — is about that group.
    private static func usage(_ usage: ProviderUsage, keeping group: String) -> ProviderUsage {
        ProviderUsage(
            account: usage.account,
            windows: usage.windows.filter { $0.scope == group },
            observedAt: usage.observedAt,
            state: usage.state,
            plan: usage.plan,
            creditBalance: usage.creditBalance
        )
    }

    private func entry(for slot: RailSlot, usage: ProviderUsage) -> RailEntry {
        let account = slot.account
        let label = settings.label(for: account)
        let pinned = settings.pinnedWindow(for: account)
        let title = slot.group.map { "\(label) · \($0)" } ?? label
        let wallet = WalletAdapter.snapshot(from: usage, title: title, pinnedWindow: pinned)
        let headline = wallet.shortQuota ?? wallet.singleQuota ?? usage.headlineWindow(preferring: pinned)

        let figure: String? = if !wallet.hasReading, case .unavailable = usage.state {
            nil
        } else if wallet.innerUsedFraction == nil {
            wallet.railCaption == "—" ? nil : wallet.railCaption
        } else {
            nil
        }

        return RailEntry(
            usage: usage,
            headline: headline,
            // Activity is per provider: transcripts do not identify accounts.
            isRunning: store.isRunning(account.provider),
            isRefreshing: store.isRefreshing(account),
            tint: settings.ringTint(for: account),
            showsBotMark: settings.showsBotMark(for: account),
            botPersona: settings.botPersona(for: account),
            botBody: settings.botBody(for: account),
            // A witnessed reset outranks a finished turn.
            botEvent: store.justReset(account) ? .limitReset
                : store.justFinishedWorking(account.provider) ? .workFinished : nil,
            botColour: settings.botColour(for: account),
            slot: slot,
            title: title,
            windowClock: settings.showsWindowClock
                ? headline?.windowClockFraction(direction: settings.windowClockDirection, at: minute)
                : nil,
            figure: figure,
            second: wallet.longQuota,
            showsRemaining: wallet.showsRemainingOnRing,
            wallet: wallet
        )
    }
}

#Preview("Floating panel") {
    FloatingUsagePanelView(
        store: UsageStore(settings: AppSettings()),
        settings: AppSettings(),
        placement: PanelPlacement()
    )
    .frame(
        width: FloatingPanelController.Layout.width,
        height: FloatingPanelController.Layout.height
    )
    .background(Color.gray.opacity(0.2))
}
