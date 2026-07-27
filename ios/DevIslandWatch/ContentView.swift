import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        NavigationStack {
            Group {
                if sessionManager.pendingEvents.isEmpty {
                    emptyState
                } else {
                    eventList
                }
            }
            .navigationTitle("Dev Island")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, isActive: !sessionManager.isPhoneReachable)

            Text("watch.ready.title")
                .font(.headline)

            // Spelled out as LocalizedStringKey rather than a bare ternary of string
            // literals: Text has both a LocalizedStringKey and a StringProtocol
            // initialiser, and a ternary can resolve to the latter — which renders the
            // key verbatim instead of localizing it.
            Text(sessionManager.isPhoneReachable
                 ? LocalizedStringKey("watch.phone.connected")
                 : LocalizedStringKey("watch.phone.disconnected"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var eventList: some View {
        List(sessionManager.pendingEvents.sorted(by: { $0.receivedAt > $1.receivedAt })) { event in
            EventCardView(event: event)
        }
        .safeAreaInset(edge: .bottom) {
            if let error = sessionManager.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, 4)
            }
        }
    }
}
