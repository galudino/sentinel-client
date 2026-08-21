//
//  SnapshotLoggingView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - Sorting

nonisolated enum SortKey: String, CaseIterable, Codable {
    case title = "Title"
    case date = "Date"
}

nonisolated enum SortDirection: String, CaseIterable, Codable {
    case ascending = "asc"
    case descending = "desc"

    var chevronIcon: String {
        switch self {
        case .ascending: "chevron.up.circle.fill"
        case .descending: "chevron.down.circle.fill"
        }
    }
}

// MARK: - SnapshotLoggingView

/// The **Snapshots** tab — the snapshot-logging browser. This concrete entry
/// point owns the per-connection ``SnapshotLoggingManager`` (bound to this peer's
/// snapshot stream + device identity), hosts the tab's `NavigationStack`, and
/// injects the manager for the generic content and child views.
///
/// The engine is generic over the snapshot type; Phase I specializes the UI to
/// ``DeviceSnapshotDataProvider``. A future snapshot type either gets its own tab
/// or a generic host, reusing the same content views unchanged.
struct SnapshotLoggingView: View {
    let peer: ConnectedPeer

    @State private var manager: SnapshotLoggingManager<DeviceSnapshotDataProvider>
    @State private var path = NavigationPath()

    init(peer: ConnectedPeer) {
        self.peer = peer
        let system = peer.system
        _manager = State(initialValue: SnapshotLoggingManager(
            provider: DeviceSnapshotDataProvider(stream: peer.snapshotStream),
            metadataProvider: {
                let serial = await (try? system.readSerialNumber()) ?? 0
                let version = try? await system.readFirmwareVersion()
                return SnapshotSessionMetadata(
                    serialNumber: serial,
                    firmwareVersion: version.map { "\($0)" } ?? "Unknown"
                )
            }
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            SnapshotLoggingContent<DeviceSnapshotDataProvider>()
                .navigationDestination(for: SnapshotRoute.self) { route in
                    switch route {
                    case let .deviceSnapshotSessionChart(session):
                        SnapshotSessionChartView<DeviceSnapshotDataProvider>(session: session)
                    }
                }
        }
        .environment(manager)
    }
}

// MARK: - SnapshotLoggingContent

/// The generic three-section browser (Configurations / Active / Completed),
/// reading its ``SnapshotLoggingManager`` from the environment so it works for any
/// snapshot type.
struct SnapshotLoggingContent<Provider: SnapshotDataProvider>: View {
    typealias S = Provider.S

    @Environment(SnapshotLoggingManager<Provider>.self) private var loggingManager

    @State private var showingCreateConfiguration = false
    @State private var showingDeleteAlert = false
    @State private var showingTimingExplanation = false
    @State private var configurationToDelete: SnapshotLoggingConfiguration<S>?
    @State private var sessionToDelete: SnapshotLoggingSession?

    @State private var configurationsSortKey: SortKey = .title
    @State private var configurationsSortDirection: SortDirection = .ascending
    @State private var activeSessionsSortKey: SortKey = .date
    @State private var activeSessionsSortDirection: SortDirection = .descending
    @State private var completedSessionsSortKey: SortKey = .date
    @State private var completedSessionsSortDirection: SortDirection = .descending

    var body: some View {
        List {
            configurationsSection
            activeSessionsSection
            completedSessionsSection
        }
        .navigationTitle(S.captureNavigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingCreateConfiguration) {
            SnapshotCreateConfigurationView<Provider>()
        }
        .sheet(isPresented: $showingTimingExplanation) {
            SnapshotTimingMetricsExplanationsView()
        }
        .alert("Delete", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: performDelete)
        } message: {
            Text(
                configurationToDelete != nil
                    ? "Are you sure you want to delete this logging configuration? This action cannot be undone."
                    : "Are you sure you want to delete this logging session? This action cannot be undone."
            )
        }
    }

    private func performDelete() {
        if let configuration = configurationToDelete {
            loggingManager.deleteConfiguration(configuration)
            configurationToDelete = nil
        } else if let session = sessionToDelete {
            loggingManager.deleteCompletedSession(session.id)
            sessionToDelete = nil
        }
    }

    // MARK: Sorting

    private func sortingButtons(
        currentSortKey: SortKey,
        currentSortDirection: SortDirection,
        onSortKeyChange: @escaping (SortKey) -> Void,
        onSortDirectionChange: @escaping (SortDirection) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            ForEach(SortKey.allCases, id: \.self) { sortKey in
                Button {
                    if currentSortKey == sortKey {
                        onSortDirectionChange(currentSortDirection == .ascending ? .descending : .ascending)
                    } else {
                        onSortKeyChange(sortKey)
                        onSortDirectionChange(.ascending)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(sortKey.rawValue)
                            .fontWeight(currentSortKey == sortKey ? .bold : .regular)
                        Group {
                            if currentSortKey == sortKey {
                                Image(systemName: currentSortDirection.chevronIcon)
                            } else {
                                Image(systemName: "circle")
                            }
                        }
                        .frame(width: 16, height: 16)
                    }
                }
                .font(.caption)
                .foregroundStyle(currentSortKey == sortKey ? Color.accentColor : .secondary)
                .buttonStyle(.bordered)
            }
        }
    }

    private func sorted<T>(
        _ items: [T],
        key: SortKey,
        direction: SortDirection,
        name: (T) -> String,
        date: (T) -> Date
    ) -> [T] {
        items.sorted { lhs, rhs in
            switch key {
            case .title:
                let comparison = name(lhs).localizedCaseInsensitiveCompare(name(rhs))
                return direction == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            case .date:
                return direction == .ascending ? date(lhs) < date(rhs) : date(lhs) > date(rhs)
            }
        }
    }

    private var sortedConfigurations: [SnapshotLoggingConfiguration<S>] {
        sorted(
            loggingManager.configurations,
            key: configurationsSortKey,
            direction: configurationsSortDirection,
            name: \.name,
            date: \.createdAt
        )
    }

    private var sortedActiveSessions: [SnapshotLoggingSession] {
        sorted(
            loggingManager.activeSessions,
            key: activeSessionsSortKey,
            direction: activeSessionsSortDirection,
            name: \.name,
            date: \.startTime
        )
    }

    private var sortedCompletedSessions: [SnapshotLoggingSession] {
        sorted(
            loggingManager.completedSessions,
            key: completedSessionsSortKey,
            direction: completedSessionsSortDirection,
            name: \.name,
            date: \.startTime
        )
    }

    // MARK: Sections

    @ViewBuilder private var configurationsSection: some View {
        Section {
            if loggingManager.configurations.isEmpty {
                emptyState(
                    icon: S.emptyStateIconName,
                    title: "No \(S.shortName) Configurations",
                    message: S.noConfigurationsText
                )
            } else {
                ForEach(sortedConfigurations) { configuration in
                    SnapshotConfigurationRowView<Provider>(configuration: configuration)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                configurationToDelete = configuration
                                showingDeleteAlert = true
                            }
                        }
                }
            }

            Button("Create New Configuration") { showingCreateConfiguration = true }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
        } header: {
            sectionHeader(
                "Configurations",
                isEmpty: loggingManager.configurations.isEmpty,
                key: configurationsSortKey,
                direction: configurationsSortDirection,
                onKey: { configurationsSortKey = $0 },
                onDirection: { configurationsSortDirection = $0 }
            )
        } footer: {
            Text(S.createConfigurationPrompt)
        }
    }

    @ViewBuilder private var activeSessionsSection: some View {
        Section {
            if loggingManager.activeSessions.isEmpty {
                emptyState(
                    icon: "play.circle",
                    title: "No Active Sessions",
                    message: "Start a logging session from a configuration to see it here."
                )
            } else {
                ForEach(sortedActiveSessions) { session in
                    SnapshotActiveSessionRowView<Provider>(session: session)
                }
            }
        } header: {
            sectionHeader(
                "Active Sessions",
                isEmpty: loggingManager.activeSessions.isEmpty,
                key: activeSessionsSortKey,
                direction: activeSessionsSortDirection,
                onKey: { activeSessionsSortKey = $0 },
                onDirection: { activeSessionsSortDirection = $0 }
            )
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Monitor and control running \(S.shortName.lowercased()) snapshot logging sessions.")
                Button { showingTimingExplanation = true } label: {
                    Label("Timing Metrics Explained", systemImage: "info.circle").font(.caption)
                }
            }
        }
    }

    @ViewBuilder private var completedSessionsSection: some View {
        Section {
            if loggingManager.completedSessions.isEmpty {
                emptyState(
                    icon: "checkmark.circle",
                    title: "No Completed Sessions",
                    message: S.noCompletedSessionsText
                )
            } else {
                ForEach(sortedCompletedSessions) { session in
                    SnapshotCompletedSessionRowView<Provider>(session: session)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                sessionToDelete = session
                                showingDeleteAlert = true
                            }
                        }
                }
            }
        } header: {
            sectionHeader(
                "Completed Sessions",
                isEmpty: loggingManager.completedSessions.isEmpty,
                key: completedSessionsSortKey,
                direction: completedSessionsSortDirection,
                onKey: { completedSessionsSortKey = $0 },
                onDirection: { completedSessionsSortDirection = $0 }
            )
        } footer: {
            Text("Export completed sessions as JSON, CSV, or binary files for analysis.")
        }
    }

    // MARK: Section helpers

    private func sectionHeader(
        _ title: String,
        isEmpty: Bool,
        key: SortKey,
        direction: SortDirection,
        onKey: @escaping (SortKey) -> Void,
        onDirection: @escaping (SortDirection) -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            if !isEmpty {
                sortingButtons(
                    currentSortKey: key,
                    currentSortDirection: direction,
                    onSortKeyChange: onKey,
                    onSortDirectionChange: onDirection
                )
            }
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

#Preview {
    SnapshotLoggingView(peer: ConnectedPeer.preview())
}
