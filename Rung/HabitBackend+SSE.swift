import Foundation
import Combine
import SwiftData

extension HabitBackendStore {

    // MARK: - SSE Stream

    func applyDashboardUpdate(_ value: AccountabilityDashboard) {
        dashboard = value
        WidgetSnapshotWriter.shared.updateBackendData(value)
        if let matchID = value.match?.id {
            // Snapshot the highest known message id before merging so we can
            // tell whether the dashboard payload carried a fresh AI reply —
            // otherwise the typing indicator hangs until its safety timeout
            // because SSE may deliver the event after this merge has already
            // de-duplicated it away.
            let prevMaxId = (liveMessagesByMatch[matchID] ?? []).map(\.id).max() ?? 0

            // Merge the dashboard snapshot with whatever SSE has already
            // delivered — dropping existing live entries would wipe an AI
            // reply that landed between the server's snapshot time and the
            // client applying the response.
            var merged: [Int64: AccountabilityDashboard.Message] = [:]
            for msg in value.menteeDashboard.messages { merged[msg.id] = msg }
            for msg in liveMessagesByMatch[matchID] ?? [] { merged[msg.id] = msg }
            liveMessagesByMatch[matchID] = merged.values.sorted { $0.createdAt < $1.createdAt }

            if aiMentorTyping, let match = value.match, match.aiMentor {
                let mentorId = match.mentor.userId
                let gotFreshAIReply = merged.values.contains { $0.senderId == mentorId && $0.id > prevMaxId }
                if gotFreshAIReply { setAIMentorTyping(false, matchId: matchID) }
            }

            startStream(for: matchID)
        } else {
            stopStream()
        }
    }

    func startStream(for matchID: Int64) {
        if streamingMatchID == matchID, streamTask != nil { return }
        stopStream()
        streamingMatchID = matchID
        streamTask = Task { [weak self] in await self?.runStreamLoop(matchID: matchID) }
    }

    func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        streamingMatchID = nil
        lastStreamEventID = nil
        streamRequestState = .idle
        refreshSyncingState()
    }

    // MARK: - Per-user SSE (cross-device real-time sync)

    func startUserStream() {
        if userStreamTask != nil { return }
        userStreamTask = Task { [weak self] in await self?.runUserStreamLoop() }
    }

    func stopUserStream() {
        userStreamTask?.cancel()
        userStreamTask = nil
        lastUserStreamEventID = nil
    }

    private func runUserStreamLoop() async {
        var backoffSeconds: TimeInterval = 1
        var attempt = 0
        while !Task.isCancelled, isAuthenticated {
            attempt += 1
            HabitBackendStore.sseLog("[UserStream] attempt #\(attempt) connecting…")
            do {
                let request = try await accountabilityRepository.userStreamRequest(
                    lastEventID: lastUserStreamEventID
                )
                let (bytes, response) = try await sseSession.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    HabitBackendStore.sseLog("[UserStream] connect failed — status \(code)")
                    throw HabitBackendError.invalidResponse
                }
                HabitBackendStore.sseLog("[UserStream] connected (attempt #\(attempt))")
                backoffSeconds = 1
                try await consumeUserStreamLines(lines: bytes.lines)
                HabitBackendStore.sseLog("[UserStream] disconnected (peer closed) — will reconnect")
            } catch {
                if Task.isCancelled {
                    HabitBackendStore.sseLog("[UserStream] task cancelled — exiting loop")
                    return
                }
                HabitBackendStore.sseLog("[UserStream] error: \(error.localizedDescription) — retrying in \(Int(backoffSeconds))s")
                try? await Task.sleep(for: .seconds(backoffSeconds))
                backoffSeconds = min(backoffSeconds * 2, 30)
            }
        }
        HabitBackendStore.sseLog("[UserStream] loop exited (cancelled=\(Task.isCancelled) authed=\(isAuthenticated))")
    }

    private func consumeUserStreamLines<S: AsyncSequence>(lines: S) async throws where S.Element == String {
        var eventName = "message"
        var eventID: String?
        var dataLines: [String] = []

        for try await raw in lines {
            if Task.isCancelled { return }
            if raw.isEmpty {
                // Blank line = event boundary.
                let payload = dataLines.joined(separator: "\n")
                if !payload.isEmpty {
                    handleUserStreamEvent(name: eventName, id: eventID, payload: payload)
                }
                eventName = "message"; eventID = nil; dataLines.removeAll(keepingCapacity: true)
                continue
            }
            if raw.hasPrefix("event:") { eventName = raw.dropFirst(6).trimmingCharacters(in: .whitespaces); continue }
            if raw.hasPrefix("id:")    { eventID   = raw.dropFirst(3).trimmingCharacters(in: .whitespaces); continue }
            if raw.hasPrefix("data:")  { dataLines.append(String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        }
    }

    private func handleUserStreamEvent(name: String, id: String?, payload: String) {
        if let id = id, !id.isEmpty { lastUserStreamEventID = id }
        switch name {
        case "habits.changed":
            HabitBackendStore.sseLog("[UserStream] habits.changed received id=\(id ?? "-") payload=\(payload)")
            Task {
                await responseCache.invalidateHabits()
                await responseCache.invalidateDashboard()
                HabitBackendStore.sseLog("[UserStream] cache invalidated; posting .habitsChangedSSE")
                await MainActor.run {
                    NotificationCenter.default.post(name: .habitsChangedSSE, object: nil)
                }
            }
        case "sleep.changed":
            // Another device just uploaded a fresh sleep snapshot.
            // SleepInsightsService observes this notification and refetches
            // the backend snapshot so the energy curve, sleep-debt readout,
            // and chronotype badge converge across devices in seconds —
            // same pattern habits.changed uses, applied to sleep data.
            HabitBackendStore.sseLog("[UserStream] sleep.changed received id=\(id ?? "-")")
            Task { @MainActor in
                NotificationCenter.default.post(name: .sleepSnapshotChangedSSE, object: nil)
            }
        case "prefs.changed":
            // Profile (username/avatar/displayName) or settings
            // (weekly-report toggle) changed on another device. Refresh
            // both — dashboard caches displayName/avatar and the
            // preferences endpoint backs the email-opt-in toggle.
            #if DEBUG
            HabitBackendStore.sseLog("[UserStream] prefs.changed received id=\(id ?? "-")")
            #endif
            Task { @MainActor in
                await responseCache.invalidateDashboard()
                await loadPreferences()
                await refreshDashboard()
                // Push the fresh displayName into Widgets so they stop
                // rendering the stale name. Without this, the rename appears
                // in the dashboard within seconds but Widgets can lag for
                // hours until the next foreground tick.
                // (Live Activity content state is streak-only — it doesn't
                // carry displayName, so no update is needed here.)
                WidgetSnapshotWriter.shared.refresh()
            }
        case "session.revoked":
            // Server hard-deleted the current user (or revoked the
            // session for some other reason). Wipe local SwiftData
            // first — ContentView listens on `.rungAccountDeleted`
            // — then tear the session down so the auth flow appears
            // immediately. After this, signing in with the same Apple
            // ID provisions a fresh account; previous habits are gone.
            HabitBackendStore.sseLog("[UserStream] session.revoked received id=\(id ?? "-") payload=\(payload)")
            Task { @MainActor in
                NotificationCenter.default.post(name: .rungAccountDeleted, object: nil)
                signOut()
            }
        case "ping", "stream.ready":
            break
        default:
            HabitBackendStore.sseLog("[UserStream] unknown event '\(name)'")
        }
    }

    private func runStreamLoop(matchID: Int64) async {
        var hadSuccessfulConnection = false
        var backoffSeconds: TimeInterval = 1

        while !Task.isCancelled, streamingMatchID == matchID, isAuthenticated {
            do {
                streamRequestState = .loading
                refreshSyncingState()
                let request = try await accountabilityRepository.streamRequest(
                    matchId: matchID, lastEventID: lastStreamEventID
                )
                // Use the shared sseSession (not URLSession.shared) so signOut
                // can invalidate it cleanly — URLSession.shared is global and
                // can't be reset without affecting other consumers.
                let (bytes, response) = try await sseSession.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw HabitBackendError.invalidResponse
                }
                if hadSuccessfulConnection { await refreshDashboard() }
                hadSuccessfulConnection = true
                backoffSeconds = 1  // reset on successful connect
                streamRequestState = .success(())
                refreshSyncingState()
                try await consumeSSELines(matchID: matchID, lines: bytes.lines)
            } catch {
                if Task.isCancelled { return }
                streamRequestState = .failure(error.localizedDescription)
                refreshSyncingState()
                // Exponential backoff for stream reconnects (cap at 30s)
                try? await Task.sleep(for: .seconds(backoffSeconds))
                backoffSeconds = min(backoffSeconds * 2, 30)
            }
        }
    }

    private func consumeSSELines<S: AsyncSequence>(matchID: Int64, lines: S) async throws where S.Element == String {
        var eventName = "message"
        var eventID: String?
        var dataLines: [String] = []

        for try await raw in lines {
            if Task.isCancelled || streamingMatchID != matchID { return }
            if raw.isEmpty {
                let payload = dataLines.joined(separator: "\n")
                if !payload.isEmpty {
                    handleStreamEvent(matchID: matchID, eventName: eventName, eventID: eventID, payload: payload)
                }
                eventName = "message"; eventID = nil; dataLines.removeAll(keepingCapacity: true)
                continue
            }
            if raw.hasPrefix("event:") { eventName = raw.dropFirst(6).trimmingCharacters(in: .whitespaces); continue }
            if raw.hasPrefix("id:")    { eventID   = raw.dropFirst(3).trimmingCharacters(in: .whitespaces); continue }
            if raw.hasPrefix("data:")  { dataLines.append(String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        }
    }

    private func handleStreamEvent(matchID: Int64, eventName: String, eventID: String?, payload: String) {
        if let id = eventID, !id.isEmpty { lastStreamEventID = id }
        switch eventName {
        case "message.created":
            guard
                let data = payload.data(using: .utf8),
                let msg = try? JSONDecoder().decode(AccountabilityDashboard.Message.self, from: data)
            else { return }
            appendMessage(msg, to: matchID)
            // Arriving messages make the cached dashboard stale
            Task { await responseCache.invalidateDashboard() }
        case "match.updated":
            Task { [weak self] in
                await self?.responseCache.invalidateDashboard()
                await self?.refreshDashboard()
            }
        case "message.read":
            _ = payload.data(using: .utf8).flatMap { try? JSONDecoder().decode(MatchStreamMessageReadEvent.self, from: $0) }
        case "ping", "stream.ready":
            break
        default:
            break
        }
    }

    private func appendMessage(_ message: AccountabilityDashboard.Message, to matchID: Int64) {
        // Clear the "typing…" indicator the moment a message from the AI
        // mentor is observed. Run this *before* the dedup guard so SSE
        // re-deliveries (server may emit the event after the dashboard
        // snapshot already imported the row) still clear the indicator.
        if let match = dashboard?.match,
           match.id == matchID,
           match.aiMentor,
           message.senderId == match.mentor.userId {
            setAIMentorTyping(false, matchId: matchID)
        }

        var msgs = liveMessagesByMatch[matchID] ?? []
        guard !msgs.contains(where: { $0.id == message.id }) else { return }
        msgs.append(message)
        // Sort chronologically so the chat view doesn't depend on insertion
        // order (dashboard snapshot + SSE deliveries can interleave).
        msgs.sort { $0.createdAt < $1.createdAt }
        if msgs.count > 60 { msgs = Array(msgs.suffix(60)) }
        liveMessagesByMatch[matchID] = msgs
    }

}
