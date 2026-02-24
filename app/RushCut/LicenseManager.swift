import Foundation
import SwiftUI

/// Manages license key activation, validation, and persistence via Polar.sh API.
@MainActor
final class LicenseManager: ObservableObject {

    // MARK: - Configuration
    // TODO: Replace with your actual Polar organization ID after creating your account
    static let organizationId = "YOUR_POLAR_ORG_ID"
    static let polarBaseURL = "https://api.polar.sh/v1/customer-portal/license-keys"

    /// How often to re-validate (7 days)
    static let revalidationInterval: TimeInterval = 7 * 24 * 60 * 60
    /// Grace period for offline use (30 days)
    static let offlineGracePeriod: TimeInterval = 30 * 24 * 60 * 60

    // MARK: - Published state

    enum LicenseState: Equatable {
        case unknown       // Haven't checked yet
        case unlicensed    // No key stored
        case validating    // Checking with Polar
        case licensed      // Valid and active
        case expired       // Key was revoked or expired
        case error(String) // Something went wrong

        static func == (lhs: LicenseState, rhs: LicenseState) -> Bool {
            switch (lhs, rhs) {
            case (.unknown, .unknown), (.unlicensed, .unlicensed),
                 (.validating, .validating), (.licensed, .licensed),
                 (.expired, .expired):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var state: LicenseState = .unknown
    @Published var activationError: String?

    // MARK: - Stored properties

    /// The license key string (persisted in Keychain)
    var licenseKey: String? {
        KeychainHelper.read(key: "licenseKey")
    }

    /// The activation ID from Polar (persisted in Keychain)
    var activationId: String? {
        KeychainHelper.read(key: "activationId")
    }

    /// Last successful validation date (persisted in UserDefaults)
    private var lastValidated: Date? {
        get { UserDefaults.standard.object(forKey: "license.lastValidated") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "license.lastValidated") }
    }

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Check license state on app launch. Runs validation if needed.
    func checkOnLaunch() async {
        guard let key = licenseKey, !key.isEmpty,
              let actId = activationId, !actId.isEmpty else {
            state = .unlicensed
            return
        }

        // Check if we need to re-validate
        if let last = lastValidated {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < Self.revalidationInterval {
                // Still within the re-validation window — assume valid
                state = .licensed
                return
            }
        }

        // Need to validate
        await validate(key: key, activationId: actId)
    }

    /// Activate a new license key. Called from the license entry UI.
    func activate(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            activationError = "Please enter a license key."
            return
        }

        state = .validating
        activationError = nil

        let label = Host.current().localizedName ?? "Mac"

        let body: [String: Any] = [
            "key": trimmed,
            "organization_id": Self.organizationId,
            "label": label,
        ]

        do {
            let result = try await postJSON(
                url: "\(Self.polarBaseURL)/activate",
                body: body
            )

            // Extract activation ID
            guard let activationIdStr = result["id"] as? String else {
                // Check if error message from Polar
                if let detail = result["detail"] as? String {
                    activationError = detail
                    state = .unlicensed
                    return
                }
                activationError = "Unexpected response from license server."
                state = .unlicensed
                return
            }

            // Success — store in Keychain
            KeychainHelper.save(key: "licenseKey", value: trimmed)
            KeychainHelper.save(key: "activationId", value: activationIdStr)
            lastValidated = Date()
            state = .licensed
            activationError = nil

        } catch {
            activationError = friendlyError(error)
            state = .unlicensed
        }
    }

    /// Validate an existing license key + activation.
    func validate(key: String, activationId actId: String) async {
        state = .validating

        let body: [String: Any] = [
            "key": key,
            "organization_id": Self.organizationId,
            "activation_id": actId,
        ]

        do {
            let result = try await postJSON(
                url: "\(Self.polarBaseURL)/validate",
                body: body
            )

            // Check status field
            if let status = result["status"] as? String, status == "granted" {
                lastValidated = Date()
                state = .licensed
            } else if let status = result["status"] as? String, status == "revoked" {
                state = .expired
            } else if let detail = result["detail"] as? String {
                // Could be an error from Polar
                handleValidationFailure(detail: detail)
            } else {
                // Unknown response but had some data — use grace period
                applyGracePeriod()
            }

        } catch {
            // Network error — apply grace period
            applyGracePeriod()
        }
    }

    /// Deactivate the current license (remove from this Mac).
    func deactivate() async {
        if let key = licenseKey, let actId = activationId {
            // Best-effort deactivation call to Polar
            let body: [String: Any] = [
                "key": key,
                "organization_id": Self.organizationId,
                "activation_id": actId,
            ]
            _ = try? await postJSON(
                url: "\(Self.polarBaseURL)/deactivate",
                body: body
            )
        }

        // Clear local data regardless
        KeychainHelper.deleteAll()
        lastValidated = nil
        state = .unlicensed
        activationError = nil
    }

    // MARK: - Private helpers

    /// If validation fails due to network issues, allow continued use within the grace period.
    private func applyGracePeriod() {
        if let last = lastValidated {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < Self.offlineGracePeriod {
                state = .licensed // Still within grace period
            } else {
                state = .expired
            }
        } else {
            state = .expired
        }
    }

    private func handleValidationFailure(detail: String) {
        let lower = detail.lowercased()
        if lower.contains("not found") || lower.contains("invalid") || lower.contains("revoked") {
            state = .expired
        } else {
            // Unknown error — apply grace period
            applyGracePeriod()
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let desc = error.localizedDescription.lowercased()
        if desc.contains("offline") || desc.contains("network") || desc.contains("internet") || desc.contains("timed out") {
            return "Could not reach the license server. Check your internet connection and try again."
        }
        if desc.contains("activation") && desc.contains("limit") {
            return "This license key has reached its activation limit (2 Macs). Deactivate another machine first, or contact support."
        }
        return "Activation failed: \(error.localizedDescription)"
    }

    /// POST JSON to a URL and return the parsed response dictionary.
    @discardableResult
    private func postJSON(url urlString: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        // Parse response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        // For error status codes, extract detail
        if httpResponse.statusCode >= 400 {
            let detail = json["detail"] as? String
                ?? (json["detail"] as? [String: Any])?["message"] as? String
                ?? "Server returned status \(httpResponse.statusCode)"
            throw LicenseError.serverError(detail)
        }

        return json
    }
}

// MARK: - Error type

enum LicenseError: LocalizedError {
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .serverError(let msg): return msg
        }
    }
}
