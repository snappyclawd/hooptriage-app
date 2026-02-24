import SwiftUI

/// License key entry screen shown on first launch or when unlicensed.
struct LicenseEntryView: View {
    @ObservedObject var license: LicenseManager
    @State private var keyInput = ""
    @State private var isActivating = false

    private let purchaseURL = URL(string: "https://polar.sh/rushcut")! // TODO: Replace with actual Polar storefront URL

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo + title
            VStack(spacing: 16) {
                RushCutLogo(size: 64)
                    .foregroundStyle(.orange)

                Text("RushCut")
                    .font(.system(size: 28, weight: .bold, design: .default))

                Text("Enter your license key to get started.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer().frame(height: 40)

            // License key input
            VStack(spacing: 12) {
                TextField("RUSHCUT_XXXX-XXXX-XXXX-XXXX", text: $keyInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .onSubmit {
                        activateKey()
                    }
                    .disabled(isActivating)

                // Error message
                if let error = license.activationError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 11))
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }

                // Activate button
                Button(action: activateKey) {
                    HStack(spacing: 6) {
                        if isActivating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isActivating ? "Activating..." : "Activate License")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActivating)
            }
            .frame(maxWidth: 380)

            Spacer().frame(height: 24)

            // Purchase link
            VStack(spacing: 8) {
                Text("Don't have a license key?")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Link(destination: purchaseURL) {
                    Text("Buy RushCut for $49")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Expired state message
            if license.state == .expired {
                VStack(spacing: 6) {
                    Divider().padding(.bottom, 8)
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Your license has expired or been revoked. Please enter a valid license key or purchase a new one.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)
            }
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func activateKey() {
        guard !keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isActivating = true
        Task {
            await license.activate(key: keyInput)
            isActivating = false
        }
    }
}
