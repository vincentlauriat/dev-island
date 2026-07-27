import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        Form {
            notificationSettingsSection
            deviceSection
            dangerSection
        }
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Notification Settings

    @ViewBuilder
    private var notificationSettingsSection: some View {
        Section("settings.section.notificationTypes") {
            Toggle(isOn: $connectionManager.notifyPermissions) {
                Label("event.type.permission", systemImage: "lock.shield")
            }
            Toggle(isOn: $connectionManager.notifyQuestions) {
                Label("event.type.question", systemImage: "questionmark.bubble")
            }
            Toggle(isOn: $connectionManager.notifyCompletions) {
                Label("settings.notify.completions", systemImage: "checkmark.circle")
            }
        }

        Section {
            Toggle(isOn: $connectionManager.silentCompletions) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.silent.title")
                    Text("settings.silent.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!connectionManager.notifyCompletions)
        } header: {
            Text("settings.section.sound")
        }
    }

    // MARK: - Device Info

    @ViewBuilder
    private var deviceSection: some View {
        Section("settings.section.pairedDevice") {
            if let macName = connectionManager.connectedMacName {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(macName)
                                .font(.body)
                            if let pairedAt = connectionManager.pairedAt {
                                Text(String(
                                    format: NSLocalizedString("settings.pairedAt", comment: "%@ is the pairing date"),
                                    pairedAt.formatted(date: .abbreviated, time: .omitted)
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    connectionStatusBadge
                }
            } else {
                HStack {
                    Image(systemName: "desktopcomputer")
                        .foregroundStyle(.secondary)
                    Text("settings.notPaired")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var connectionStatusBadge: some View {
        switch connectionManager.state {
        case .connected:
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text("connection.badge.connected")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        case .paired:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("connection.badge.connecting")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .discovering:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("connection.badge.searching")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .disconnected:
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                Text("connection.badge.offline")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Danger Zone

    @ViewBuilder
    private var dangerSection: some View {
        Section {
            if connectionManager.connectedMacName != nil {
                Button(role: .destructive) {
                    connectionManager.disconnect()
                } label: {
                    Label("settings.disconnect", systemImage: "xmark.circle")
                }
            }

            Button {
                connectionManager.startDiscovery()
            } label: {
                Label("settings.rescan", systemImage: "arrow.clockwise")
            }
        }
    }
}
