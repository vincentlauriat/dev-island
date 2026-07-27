import SwiftUI

struct PairingView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMac: DiscoveredMac?
    @State private var pairingCode = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var showManualEntry = false
    @State private var manualHost = ""
    @State private var manualPort = "7890"
    @State private var manualCode = ""
    @State private var manualError: String?
    @State private var isManualPairing = false

    var body: some View {
        NavigationStack {
            Group {
                if selectedMac == nil {
                    macListView
                } else {
                    codeInputView
                }
            }
            .navigationTitle("pairing.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        connectionManager.discovery.stopBrowsing()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            connectionManager.discovery.startBrowsing()
        }
    }

    // MARK: - Mac List

    @ViewBuilder
    private var macListView: some View {
        List {
            if connectionManager.discovery.isSearching {
                Section {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("pairing.searching")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !connectionManager.discovery.discoveredMacs.isEmpty {
                Section("pairing.section.found") {
                    ForEach(connectionManager.discovery.discoveredMacs) { mac in
                        Button {
                            selectedMac = mac
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(.blue)
                                    .frame(width: 32)

                                VStack(alignment: .leading) {
                                    Text(mac.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            if !connectionManager.discovery.isSearching && connectionManager.discovery.discoveredMacs.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)

                        Text("pairing.notFound.title")
                            .font(.headline)

                        Text("pairing.notFound.message")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("pairing.retry") {
                            connectionManager.discovery.startBrowsing()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }
            }

            Section {
                Button {
                    showManualEntry = true
                } label: {
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundStyle(.orange)
                            .frame(width: 32)
                        Text("pairing.manual.entry")
                    }
                }
            }
        }
        .sheet(isPresented: $showManualEntry) {
            manualEntrySheet
        }
    }

    // MARK: - Manual Entry Sheet

    private var manualEntrySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("pairing.manual.host", text: $manualHost)
                        .keyboardType(.decimalPad)
                    TextField("pairing.manual.port", text: $manualPort)
                        .keyboardType(.numberPad)
                    TextField("pairing.manual.code", text: $manualCode)
                        .keyboardType(.numberPad)
                        .onChange(of: manualCode) { _, newValue in
                            let filtered = String(newValue.filter(\.isNumber).prefix(4))
                            if filtered != newValue {
                                manualCode = filtered
                            }
                        }
                } footer: {
                    Text("pairing.manual.footer")
                }

                if let manualError {
                    Section {
                        Text(manualError)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        performManualPairing()
                    } label: {
                        if isManualPairing {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("pairing.manual.submit")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(manualHost.isEmpty || manualCode.count != 4 || isManualPairing)
                }
            }
            .navigationTitle("pairing.manual.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        showManualEntry = false
                    }
                }
            }
        }
    }

    // MARK: - Manual Pairing

    private func performManualPairing() {
        guard let port = UInt16(manualPort) else {
            manualError = NSLocalizedString("pairing.manual.invalidPort", comment: "")
            return
        }
        isManualPairing = true
        manualError = nil

        Task {
            do {
                try await connectionManager.pairManual(host: manualHost, port: port, code: manualCode)
                showManualEntry = false
            } catch {
                manualError = error.localizedDescription
                manualCode = ""
            }
            isManualPairing = false
        }
    }

    // MARK: - Code Input

    @ViewBuilder
    private var codeInputView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text(selectedMac?.name ?? "Mac")
                    .font(.title3)
                    .fontWeight(.medium)
            }

            VStack(spacing: 12) {
                Text("pairing.codePrompt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("0000", text: $pairingCode)
                    .keyboardType(.numberPad)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 200)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: pairingCode) { _, newValue in
                        // Limit to 4 digits
                        let filtered = String(newValue.filter(\.isNumber).prefix(4))
                        if filtered != newValue {
                            pairingCode = filtered
                        }
                    }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Button {
                performPairing()
            } label: {
                if isPairing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("pairing.submit")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(pairingCode.count != 4 || isPairing)
            .padding(.horizontal, 40)

            Button("pairing.chooseAnother") {
                selectedMac = nil
                pairingCode = ""
                errorMessage = nil
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.top, 40)
    }

    // MARK: - Pairing

    private func performPairing() {
        guard let mac = selectedMac else { return }
        isPairing = true
        errorMessage = nil

        Task {
            do {
                try await connectionManager.pair(mac: mac, code: pairingCode)
            } catch {
                errorMessage = error.localizedDescription
                pairingCode = ""
            }
            isPairing = false
        }
    }
}
