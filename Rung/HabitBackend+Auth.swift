import Foundation
import Combine
import SwiftData

extension HabitBackendStore {

    // MARK: - Auth

    func signIn(username: String, password: String) async {
        authRequestState = .loading; refreshSyncingState()
        do {
            let session = try await authRepository.signIn(username: username, password: password)
            applySession(session)
            statusMessage = nil
            errorMessage = nil
            authRequestState = .success(())
        } catch {
            errorMessage = error.localizedDescription
            authRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    /// Sign in with Apple. The caller (AuthViews) hands us the verified
    /// identityToken from `ASAuthorizationAppleIDCredential`, the
    /// one-time `authorizationCode` (nil for returning sign-ins where
    /// Apple already linked the account), and the optional name Apple
    /// returns on first sign-in. Backend verifies the token, exchanges
    /// the code for a refresh token (so it can later call Apple's
    /// `/auth/revoke` on account deletion per App Store compliance),
    /// and returns the same JWT pair as password login.
    func signInWithApple(identityToken: String, authorizationCode: String?, displayName: String?) async {
        authRequestState = .loading; refreshSyncingState()
        do {
            let session = try await authRepository.signInWithApple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                displayName: displayName
            )
            applySession(session)
            statusMessage = nil
            errorMessage = nil
            authRequestState = .success(())
            // Setup overlay decision, in priority order:
            //   1. session.isNewUser  → fresh Apple account, always show setup.
            //   2. server says profileSetupCompleted=false → user quit
            //      mid-setup on a previous launch (or different device);
            //      re-land them on the setup screen synchronously off
            //      this auth response, no dashboard flash.
            //   3. server says profileSetupCompleted=true → clear the
            //      flag (covers users who finished setup elsewhere).
            //   4. server omitted the field (legacy backend) → defer to
            //      the existing async /me reconcile path.
            let serverCompleted = session.profileSetupCompleted
            let needsSetup = session.isNewUser || (serverCompleted == false)
            if needsSetup {
                requiresProfileSetup = true
                if let uid = currentUserId {
                    UserDefaults.standard.set(true, forKey: Self.profileSetupPendingKey(for: uid))
                }
                if session.isNewUser { justRegistered = true }
                // Stash whatever Apple returned in `fullName` (only
                // populated on the very first authorization) so the
                // setup screen can prefill the "Your name" field.
                // When this is nil, the screen requires the user to
                // type a name — that's the fix for private-relay
                // email accounts that previously ended up with a
                // random-looking hash as their display name.
                let trimmed = displayName?.trimmingCharacters(in: .whitespaces) ?? ""
                pendingAppleFullName = trimmed.isEmpty ? nil : trimmed
            } else if serverCompleted == true {
                requiresProfileSetup = false
                if let uid = currentUserId {
                    UserDefaults.standard.removeObject(forKey: Self.profileSetupPendingKey(for: uid))
                }
                pendingAppleFullName = nil
            } else {
                // Legacy backend (no flag in response) — let the async
                // reconcile decide. Don't touch requiresProfileSetup so
                // any UserDefaults primer set earlier survives.
                pendingAppleFullName = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            authRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    /// Submits the user's chosen username + avatar to the backend after
    /// a fresh Apple sign-up. Clears `requiresProfileSetup` on success
    /// so the UI can hand off to the regular onboarding flow.
    ///
    /// Error shape matters here — the backend may *succeed* on write but
    /// the client may fail to decode the response (e.g. a Jackson schema
    /// drift). In that case we'd soft-lock the user on the setup screen
    /// despite the profile being persisted. To avoid the loop, we
    /// inspect the error: `invalidResponse` means the server likely
    /// committed; every other case (network, 4xx with recognizable
    /// message) leaves the flag set so the user can retry.
    func setupAppleProfile(username: String, avatarURL: String, displayName: String?) async -> Bool {
        authRequestState = .loading; refreshSyncingState()
        defer { refreshSyncingState() }
        do {
            try await authRepository.setupProfile(
                username: username,
                avatarURL: avatarURL,
                displayName: displayName
            )
            if let uid = currentUserId {
                UserDefaults.standard.removeObject(forKey: Self.profileSetupPendingKey(for: uid))
            }
            requiresProfileSetup = false
            pendingAppleFullName = nil
            errorMessage = nil
            authRequestState = .success(())
            return true
        } catch {
            // No more silently-pretend-success on invalidResponse — that path
            // masked half-provisioned accounts where the server actually
            // failed but the decoder happened to throw before we could
            // surface the failure. Always surface the error so the user
            // re-prompts; `requiresProfileSetup` stays true so they can retry.
            errorMessage = error.localizedDescription
            authRequestState = .failure(error.localizedDescription)
            return false
        }
    }

    /// Cold-launch reconciliation against the V15 `profile_setup_completed`
    /// flag. Local UserDefaults primes the overlay before the network
    /// returns; this method is the source of truth that overrides it.
    /// Silently no-ops on network failure — the local primer is the
    /// fallback, so the worst case is a one-launch lag in either
    /// direction.
    func reconcileProfileSetupFromServer() async {
        guard isAuthenticated else { return }
        do {
            let status = try await authRepository.fetchMe()
            await MainActor.run {
                if status.profileSetupCompleted {
                    // Server confirms setup is done. Drop any local
                    // pending flag (e.g. user finished setup on another
                    // device) so this device stops showing the overlay.
                    if requiresProfileSetup {
                        requiresProfileSetup = false
                    }
                    if let uid = currentUserId {
                        UserDefaults.standard.removeObject(forKey: Self.profileSetupPendingKey(for: uid))
                    }
                } else {
                    // Server says setup is still pending — surface the
                    // overlay and persist so we still know on the next
                    // cold launch even if the network is offline.
                    requiresProfileSetup = true
                    if let uid = currentUserId {
                        UserDefaults.standard.set(true, forKey: Self.profileSetupPendingKey(for: uid))
                    }
                }
            }
        } catch {
            // Silent — Fix-A's UserDefaults flag (if any) already drove
            // the right initial state.
        }
    }

    /// Live availability probe used by the profile-setup screen so the
    /// "this is taken" feedback is in front of the user before they tap
    /// Continue. Falls back to `true` on transient network errors so a
    /// flaky connection doesn't permanently block the screen.
    func isUsernameAvailable(_ username: String) async -> Bool {
        do {
            return try await authRepository.isUsernameAvailable(username)
        } catch {
            return true
        }
    }

    func requestEmailVerification(email: String) async {
        authRequestState = .loading; refreshSyncingState()
        do {
            try await authRepository.requestEmailVerification(email: email)
            statusMessage = "Verification code sent to \(email)"
            errorMessage = nil
            authRequestState = .success(())
        } catch {
            errorMessage = error.localizedDescription
            authRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func register(
        username: String,
        email: String,
        password: String,
        avatarURL: String,
        verificationCode: String
    ) async {
        authRequestState = .loading; refreshSyncingState()
        do {
            let session = try await authRepository.register(
                username: username,
                email: email,
                password: password,
                avatarURL: avatarURL,
                verificationCode: verificationCode
            )
            applySession(session)
            justRegistered = true
            statusMessage = nil
            errorMessage = nil
            authRequestState = .success(())
        } catch {
            errorMessage = error.localizedDescription
            authRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func signOut() {
        stopStream()
        stopUserStream()
        // Invalidate the SSE transport so any bytes still in flight from the
        // prior session don't leak into a subsequent sign-in. Without this,
        // signing in as a different user could see the previous user's
        // residual `habits.changed` events bleed through.
        resetSseSession()
        clearSession()
        Task {
            await apiClient.logout()
            await apiClient.clearSession()
        }
    }

    func deleteAccount() async {
        do {
            let _: EmptyResponse = try await apiClient.authorizedRequest(
                path: "/api/users/me", method: "DELETE"
            )
            errorMessage = nil
            statusMessage = "Account deleted from server."
            // Tell the dashboard to wipe SwiftData before signOut clears
            // tokens — otherwise any in-flight 401 handling could race
            // the local-data wipe.
            NotificationCenter.default.post(name: .rungAccountDeleted, object: nil)
            signOut()
        } catch {
            errorMessage = "Couldn’t delete account on server: \(error.localizedDescription)"
            statusMessage = nil
        }
    }

    private struct EmptyResponse: Decodable {}

}
