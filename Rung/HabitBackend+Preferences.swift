import Foundation
import Combine
import SwiftData

extension HabitBackendStore {

    // MARK: - Preferences

    func loadPreferences() async {
        guard token != nil else { return }
        preferencesRequestState = .loading
        do {
            let value = try await preferencesRepository.get()
            preferences = value
            preferencesRequestState = .success(value)
        } catch {
            handleAuthenticatedRequestError(error)
            preferencesRequestState = .failure(error.localizedDescription)
        }
    }

    /// Optimistically flips the local toggle, then syncs with the server. On
    /// failure the previous value is restored so the UI never disagrees with
    /// the persisted state.
    func setEmailOptIn(_ enabled: Bool) async {
        guard token != nil else { return }
        let previous = preferences
        preferences = UserPreferences(emailOptIn: enabled)
        preferencesRequestState = .loading
        do {
            let value = try await preferencesRepository.update(emailOptIn: enabled)
            preferences = value
            preferencesRequestState = .success(value)
        } catch {
            preferences = previous
            handleAuthenticatedRequestError(error)
            preferencesRequestState = .failure(error.localizedDescription)
        }
    }

}
