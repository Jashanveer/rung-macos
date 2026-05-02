import Foundation
import Combine
import SwiftData

extension HabitBackendStore {

    // MARK: - Dashboard (cache-aware)

    func refreshDashboard() async {
        guard token != nil else { return }

        // Return cached dashboard if fresh (e.g., refreshDashboard called multiple times quickly)
        if let cached = await responseCache.cachedDashboard() {
            if case .success = dashboardRequestState { return }  // already showing latest
            applyDashboardUpdate(cached)
            dashboardRequestState = .success(cached)
            return
        }

        dashboardRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.dashboard()
            await syncSessionFromClient()
            await responseCache.cacheDashboard(value)
            applyDashboardUpdate(value)
            dashboardRequestState = .success(value)
            errorMessage = nil
        } catch {
            handleAuthenticatedRequestError(error)
            dashboardRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    // MARK: - Accountability (write methods always invalidate dashboard cache)

    func assignMentor() async {
        guard token != nil else { return }
        mentorRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.assignMentor()
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            statusMessage = "Mentor match updated"
            errorMessage = nil
            mentorRequestState = .success(())
        } catch {
            handleAuthenticatedRequestError(error)
            mentorRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func sendMenteeMessage(matchId: Int64, message: String) async {
        guard token != nil else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = Date()
        if let lastAt = lastSentMessageAt, now.timeIntervalSince(lastAt) < 0.8 {
            statusMessage = "You're sending too fast. Try again."
            return
        }
        if
            let lastText = lastSentMessageText,
            let lastAt = lastSentMessageAt,
            now.timeIntervalSince(lastAt) < 5,
            lastText.caseInsensitiveCompare(trimmed) == .orderedSame
        {
            statusMessage = "Duplicate message blocked."
            return
        }

        lastSentMessageAt = now
        lastSentMessageText = trimmed
        messageRequestState = .loading; refreshSyncingState()

        // Immediately raise the "mentor is typing…" indicator for AI matches
        // so the UI has something to show during the async Gemini round-trip.
        // Cleared in `appendMessage` the moment the AI reply lands via SSE,
        // or after a safety timeout if the stream is slow.
        let isAI = dashboard?.match?.aiMentor ?? false
        if isAI {
            setAIMentorTyping(true, matchId: matchId)
        }
        do {
            let value = try await accountabilityRepository.sendMenteeMessage(matchId: matchId, message: trimmed)
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            messageRequestState = .success(())
            errorMessage = nil
        } catch {
            setAIMentorTyping(false, matchId: matchId)
            handleAuthenticatedRequestError(error)
            messageRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    /// Flips the typing indicator on/off. While the indicator is on, also
    /// runs a light polling loop that refreshes the dashboard every 3s as a
    /// fallback for any case where the SSE event gets dropped (flaky
    /// network, proxy buffering, etc.) — a dashboard refresh will pick up
    /// the AI message via the merge in `applyDashboardUpdate`, which in
    /// turn fires `appendMessage` and clears this indicator.
    func setAIMentorTyping(_ typing: Bool, matchId: Int64) {
        aiMentorTyping = typing
        aiMentorTypingTimeoutTask?.cancel()
        aiMentorTypingTimeoutTask = nil
        guard typing else { return }
        aiMentorTypingTimeoutTask = Task { [weak self] in
            var elapsed: TimeInterval = 0
            let poll: TimeInterval = 3
            let maxWait: TimeInterval = 45
            while elapsed < maxWait {
                try? await Task.sleep(for: .seconds(poll))
                if Task.isCancelled { return }
                guard let self, self.aiMentorTyping else { return }
                await self.responseCache.invalidateDashboard()
                await self.refreshDashboard()
                elapsed += poll
            }
            // Hard timeout — clear the indicator so the UI doesn't hang
            // forever if the AI call failed silently.
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { self.aiMentorTyping = false }
        }
    }

    func requestFriend(userID: Int64) async {
        guard token != nil else { return }
        friendRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.requestFriend(friendUserID: userID)
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            friendSearchResults.removeAll { $0.userId == userID }
            statusMessage = "Following"
            errorMessage = nil
            friendRequestState = .success(())
        } catch {
            handleAuthenticatedRequestError(error)
            friendRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func searchFriends(query: String) async {
        guard token != nil else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            friendSearchResults = []
            friendSearchRequestState = .idle
            refreshSyncingState()
            return
        }

        friendSearchRequestState = .loading; refreshSyncingState()
        do {
            let results = try await accountabilityRepository.searchFriends(query: trimmed)
            await syncSessionFromClient()
            friendSearchResults = results
            friendSearchRequestState = .success(results)
            errorMessage = nil
        } catch {
            handleAuthenticatedRequestError(error)
            friendSearchRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func useStreakFreeze(dateKey: String) async {
        guard token != nil else { return }
        streakFreezeRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.useStreakFreeze(dateKey: dateKey)
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            statusMessage = "Streak freeze applied for \(dateKey)"
            errorMessage = nil
            streakFreezeRequestState = .success(())
        } catch {
            handleAuthenticatedRequestError(error)
            streakFreezeRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    /// Reverts the most recent streak-freeze usage, provided the server is
    /// still within its undo grace window. Paired with the 5-second undo
    /// banner in `StreakFreezeCard`.
    func undoStreakFreeze() async {
        guard token != nil else { return }
        streakFreezeRequestState = .loading; refreshSyncingState()
        do {
            let value = try await accountabilityRepository.undoStreakFreeze()
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
            statusMessage = "Streak freeze undone"
            errorMessage = nil
            streakFreezeRequestState = .success(())
        } catch {
            handleAuthenticatedRequestError(error)
            streakFreezeRequestState = .failure(error.localizedDescription)
        }
        refreshSyncingState()
    }

    func registerDeviceToken(_ token: Data) async {
        guard isAuthenticated else { return }
        let hex = token.map { String(format: "%02.2hhx", $0) }.joined()
        do { try await deviceRepository.registerToken(hex, platform: "macos") } catch {}
    }

    func markMatchRead(matchID: Int64?) async {
        guard let matchID, token != nil else { return }
        do { try await accountabilityRepository.markMatchRead(matchId: matchID) } catch {
            handleAuthenticatedRequestError(error)
        }
    }

    func sendNudge(matchId: Int64) async {
        guard token != nil else { return }
        do {
            let value = try await accountabilityRepository.sendNudge(matchId: matchId)
            await syncSessionFromClient()
            await responseCache.invalidateDashboard()
            applyDashboardUpdate(value)
        } catch {
            handleAuthenticatedRequestError(error)
        }
    }

}
