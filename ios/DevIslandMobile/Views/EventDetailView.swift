import SwiftUI

struct EventDetailView: View {
    let event: WatchEvent
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        List {
            headerSection
            detailSection

            if !event.isResolved, event.requestID != nil {
                actionSection
            }

            if event.isResolved {
                resolutionSection
            }

            metadataSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("event.detail.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(event.isResolved ? Color.green.opacity(0.15) : event.iconColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: event.isResolved ? "checkmark.circle.fill" : event.iconName)
                        .font(.system(size: 26))
                        .foregroundStyle(event.isResolved ? .green : event.iconColor)
                }

                Text(event.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Text(event.agentTool)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1), in: Capsule())

                    Text(eventTypeLabel)
                        .font(.caption)
                        .foregroundStyle(event.iconColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(event.iconColor.opacity(0.1), in: Capsule())

                    if event.isResolved {
                        Text("event.resolved.badge")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.1), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailSection: some View {
        switch event.kind {
        case let .permissionRequested(title, summary, _, primaryAction, secondaryAction):
            Section("event.type.permission") {
                LabeledContent("event.field.action", value: title)
                LabeledContent("event.field.summary", value: summary)
                if let dir = event.workingDirectory {
                    LabeledContent("event.field.workingDirectory", value: dir)
                }
                HStack {
                    Text("event.field.availableActions")
                    Spacer()
                    Text(primaryAction)
                        .foregroundStyle(.green)
                    Text("/")
                        .foregroundStyle(.secondary)
                    Text(secondaryAction)
                        .foregroundStyle(.red)
                }
            }

        case let .questionAsked(title, options, _):
            Section("event.type.question") {
                Text(title)
                    .font(.body)
            }
            if !options.isEmpty {
                Section("event.section.options") {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        Text(option)
                    }
                }
            }

        case let .sessionCompleted(summary):
            Section("event.section.completionSummary") {
                Text(summary)
                    .font(.body)
            }
        }
    }

    // MARK: - Actions (for unresolved actionable events)

    @ViewBuilder
    private var actionSection: some View {
        Section {
            switch event.kind {
            case let .permissionRequested(_, _, requestID, primaryAction, secondaryAction):
                Button {
                    postResolution(requestID: requestID, action: primaryAction.lowercased())
                } label: {
                    Label(primaryAction, systemImage: "checkmark.circle")
                }

                Button(role: .destructive) {
                    postResolution(requestID: requestID, action: secondaryAction.lowercased())
                } label: {
                    Label(secondaryAction, systemImage: "xmark.circle")
                }

            case let .questionAsked(_, options, requestID):
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        postResolution(requestID: requestID, action: option)
                    } label: {
                        Label(option, systemImage: "arrow.right.circle")
                    }
                }

            case .sessionCompleted:
                EmptyView()
            }
        } header: {
            Text("event.section.actions")
        }
    }

    // MARK: - Resolution Info

    @ViewBuilder
    private var resolutionSection: some View {
        Section("event.section.resolution") {
            if let action = event.resolvedAction {
                LabeledContent("event.field.action", value: action)
            }
            if let resolvedAt = event.resolvedAt {
                LabeledContent("event.field.resolvedAt") {
                    // style: .relative renders a bare duration ("3 minutes"), which is why
                    // the original appended a separate "前". .relative(presentation: .named)
                    // emits the whole localized phrase instead — "3 minutes ago",
                    // "il y a 3 minutes", "3分钟前" — so no suffix has to be glued on.
                    Text(resolvedAt, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Metadata

    @ViewBuilder
    private var metadataSection: some View {
        Section("event.section.metadata") {
            LabeledContent("Session ID") {
                Text(event.sessionID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            LabeledContent("event.field.timestamp") {
                Text(event.timestamp, format: .dateTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var eventTypeLabel: String {
        switch event.kind {
        case .permissionRequested: return NSLocalizedString("event.type.permission", comment: "")
        case .questionAsked: return NSLocalizedString("event.type.question", comment: "")
        case .sessionCompleted: return NSLocalizedString("event.type.completion", comment: "")
        }
    }

    private func postResolution(requestID: String, action: String) {
        Task {
            do {
                try await connectionManager.postResolution(requestID: requestID, action: action)
                connectionManager.markEventResolved(requestID: requestID, action: action)
            } catch {
                // Error is handled via connectionError
            }
        }
    }
}
