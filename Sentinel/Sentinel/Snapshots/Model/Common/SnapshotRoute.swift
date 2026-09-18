//
//  SnapshotRoute.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

// MARK: - SnapshotRoute

/// Value-based navigation destinations pushed onto the Snapshots tab's
/// `NavigationStack`. A concrete ``Snapshot`` maps a completed session to its
/// chart route via ``Snapshot/chartRoute(for:)``, so the generic session list can
/// navigate to a type-appropriate chart without knowing the snapshot type.
///
/// Sentinel's navigation is per-tab (`MainTabView` gives each tab its own
/// `NavigationStack`), so this is the Snapshots-tab analogue of the app's
/// higher-level `AppState` — scoped to snapshot drill-downs only.
enum SnapshotRoute: Hashable {
    /// The per-session chart for a completed device-snapshot session.
    case deviceSnapshotSessionChart(session: SnapshotLoggingSession)
}
