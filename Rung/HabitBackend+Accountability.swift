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

    /// Fire-and-forget recovery-freeze probe. Backend gates on the
    /// user's stored sleep snapshot (debt ≥ 4 h) and a 20 h cooldown,
    /// so calling this on every cold launch / foreground transition is
    /// safe — at most one freeze gets granted per recovery window.
    /// On grant, surfaces a toast via `recoveryFreezeJustGranted` so
    /// the dashboard can flash "rest day — freeze added" once and move
    /// on. Quiet failure on network / not-fatigued / cooldown.
    @MainActor
    func requestRecoveryFreezeIfFatigued() async {
        guard token != nil else { return }
        let beforeCount = dashboard?.rewards.freezesAvailable ?? 0
        do {
            let value = try await accountabilityRepository.recoveryFreeze()
            await responseCache.cacheDashboard(value)
            applyDashboardUpdate(value)
            let afterCount = value.rewards.freezesAvailable
            if afterCount > beforeCount {
                recoveryFreezeJustGranted = true
                statusMessage = "Rest day — we added a freeze. You're under-slept; protect the streak."
            }
        } catch {
            // Quiet — endpoint is best-effort and the body of the
            // dashboard request handles the real error UX.
        }
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
        } catch HabitBackendError.network {
            // Offline send — queue the message in the local outbox so
            // it auto-drains the moment we regain connectivity. Surface
            // a soft "queued" status instead of a hard send-failure
            // toast: the user wrote it, we promised to deliver it, and
            // we're holding the receipt.
            setAIMentorTyping(false, matchId: matchId)
            enqueueOutboundMentorMessage(matchId: matchId, body: trimmed)
            messageRequestState = .success(())
            errorMessage = Self.offlineStatusMessage
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
        do {
            try await accountabilityRepository.markMatchRead(matchId: matchID)
            // Optimistic local clear — the SSE `liveMessagesByMatch`
            // cache holds messages with their original `nudge=true`
            // flag, and the unread badge on the mentor character sums
            // those flags. Without this mutate the badge stays stuck
            // at the pre-open count until the next dashboard refresh
            // (and even then, the live cache wins, so it never clears
            // for users with active SSE streams). Replace each cached
            // message with a copy where `nudge=false` so the badge
            // recomputes to 0 immediately on chat open.
            clearLocalNudgeFlags(matchID: matchID)
        } catch {
            handleAuthenticatedRequestError(error)
        }
    }

    /// Strips `nudge=true` from every cached message for `matchID` —
    /// used by `markMatchRead` so the unread counter on the mentor
    /// avatar zeroes out the moment the chat opens. Only touches the
    /// SSE live cache because `messages()` reads that array first
    /// when it exists; the dashboard snapshot itself is `let`-bound
    /// (immutable), and the openChat flow follows this call with a
    /// dashboard invalidate + refresh that picks up the server-fresh
    /// `nudge=false` rows for the dashboard slot.
    private func clearLocalNudgeFlags(matchID: Int64) {
        guard let live = liveMessagesByMatch[matchID] else { return }
        liveMessagesByMatch[matchID] = live.map(Self.withNudgeCleared)
    }

    private static func withNudgeCleared(_ msg: AccountabilityDashboard.Message) -> AccountabilityDashboard.Message {
        guard msg.nudge else { return msg }
        return AccountabilityDashboard.Message(
            id: msg.id,
            senderId: msg.senderId,
            senderName: msg.senderName,
            message: msg.message,
            nudge: false,
            createdAt: msg.createdAt
        )
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
