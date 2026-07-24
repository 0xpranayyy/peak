import SwiftUI

struct TradingSettingsView: View {
    @EnvironmentObject private var tradingConfig: TradingConfigStore
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL: String = ""
    @State private var appToken: String = ""
    @State private var statusMessage: String?
    @State private var isChecking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.10:8080", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("APP_TOKEN", text: $appToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Trading proxy")
                } footer: {
                    Text("Run Peak’s backend/ proxy on your Mac or a server. The private key stays on the proxy — never in the iOS app.")
                }

                Section {
                    Button {
                        Task { await checkHealth() }
                    } label: {
                        if isChecking {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Test connection")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || appToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if tradingConfig.isConfigured {
                    Section {
                        Button("Disconnect trading", role: .destructive) {
                            tradingConfig.clear()
                            baseURL = ""
                            appToken = ""
                            statusMessage = "Trading disconnected."
                        }
                    }
                }
            }
            .navigationTitle("Trading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        tradingConfig.save(baseURL: baseURL, appToken: appToken)
                        dismiss()
                    }
                    .disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || appToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                baseURL = tradingConfig.baseURLString
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func checkHealth() async {
        isChecking = true
        defer { isChecking = false }
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedToken = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL)?.appendingPathComponent("health") else {
            statusMessage = "Invalid URL."
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                statusMessage = "No response."
                return
            }
            if http.statusCode == 200 {
                let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let funder = root?["funder"] as? String
                statusMessage = funder.map { "Connected. Funder \($0.prefix(8))…" } ?? "Connected."
            } else {
                statusMessage = "HTTP \(http.statusCode)"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
