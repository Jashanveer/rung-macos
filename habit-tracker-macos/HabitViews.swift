import SwiftData
import SwiftUI

struct TodayHeader: View {
    let greeting: String
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .center, spacing: isCompact ? 4 : 8) {
            Text(greeting)
                .font(.system(size: isCompact ? 22 : 30, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
                .frame(maxWidth: 480)
        }
        .padding(.vertical, isCompact ? 6 : 12)
    }
}

struct AddHabitBar: View {
    @Binding var newHabitTitle: String
    @Binding var selectedType: HabitEntryType
    let onAddHabit: (HabitEntryType) -> Void

    @State private var isHovered = false
    @State private var showValidationError = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(placeholderText, text: $newHabitTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.leading, 16)
                    .focused($fieldFocused)
                    .onChange(of: newHabitTitle) { _, _ in showValidationError = false }
                    .onSubmit(attemptAdd)

                HabitEntryTypeToggle(selection: $selectedType)

                if !newHabitTitle.isEmpty {
                    Button(action: attemptAdd) {
                        Text("Add")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(CleanShotTheme.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.82, anchor: .trailing).combined(with: .opacity))
                }
            }
            .padding(.trailing, newHabitTitle.isEmpty ? 16 : 5)
            .frame(height: 46)
            .cleanShotSurface(
                shape: Capsule(),
                level: .control,
                isActive: fieldFocused || isHovered
            )
            .animation(.easeOut(duration: 0.15), value: newHabitTitle.isEmpty)
            .animation(.smooth(duration: 0.16), value: fieldFocused)
            .onHover { isHovered = $0 }

            if showValidationError {
                Text("Give your \(selectedType.title.lowercased()) a real name — something you'd actually say out loud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showValidationError)
    }

    private var placeholderText: String {
        "Add a new \(selectedType.title.lowercased())..."
    }

    private func attemptAdd() {
        guard isLikelyMeaningful(newHabitTitle) else {
            withAnimation { showValidationError = true }
            return
        }
        showValidationError = false
        onAddHabit(selectedType)
    }

    private func isLikelyMeaningful(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let letterChars = trimmed.filter { $0.isLetter }
        guard letterChars.count >= 2 else { return false }

        let lower = letterChars.lowercased()

        // Must have at least one vowel — catches ";klj", "sdfgh", pure consonant mash.
        // 'y' counts so "Gym", "Sky", "Lynx" all pass.
        let vowels = lower.filter { "aeiouy".contains($0) }
        guard !vowels.isEmpty else { return false }

        // Short names with a vowel ("Run", "Gym", "Yoga", "HIIT") are fine
        if lower.count <= 5 { return true }

        // Vowel ratio too low — "sdfjklsd" ≈ 0%
        let ratio = Double(vowels.count) / Double(lower.count)
        if ratio < 0.10 { return false }

        // Repeating half-pattern — "asdfasdf", "sdfsdf"
        let chars = Array(lower)
        let half = chars.count / 2
        if String(chars.prefix(half)) == String(chars.suffix(half)) { return false }

        // All same character
        if Set(lower).count == 1 { return false }

        // 6+ consecutive consonants in a row — not a real word
        let consonants = Set("bcdfghjklmnpqrstvwxz")
        var run = 0
        for ch in lower {
            run = consonants.contains(ch) ? run + 1 : 0
            if run >= 6 { return false }
        }

        return true
    }
}

private struct HabitEntryTypeToggle: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: HabitEntryType

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HabitEntryType.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = option
                    }
                } label: {
                    Image(systemName: option.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selection == option ? Color.white : .secondary)
                        .frame(width: 20, height: 18)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == option ? tint(for: option) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(option.title)
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(CleanShotTheme.controlFill(for: colorScheme))
        )
    }

    private func tint(for type: HabitEntryType) -> Color {
        switch type {
        case .task:
            return CleanShotTheme.accent
        case .habit:
            return CleanShotTheme.success
        }
    }
}

struct HabitListSection: View {
    let habits: [Habit]
    let todayKey: String
    let onToggle: (Habit) -> Void
    let onDelete: (Habit) -> Void
    var clusters: [AccountabilityDashboard.HabitTimeCluster] = []
    var stampNamespace: Namespace.ID? = nil

    private var doneCount: Int {
        habits.filter { $0.completedDayKeys.contains(todayKey) }.count
    }

    private func cluster(for habit: Habit) -> AccountabilityDashboard.HabitTimeCluster? {
        clusters.first { $0.habitTitle == habit.title }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's list")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(doneCount)/\(habits.count) done")
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 4)

            LazyVStack(spacing: 6) {
                ForEach(habits) { habit in
                    HabitCard(
                        habit: habit,
                        todayKey: todayKey,
                        onToggle: onToggle,
                        onDelete: onDelete,
                        cluster: cluster(for: habit),
                        stampNamespace: stampNamespace
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct MinimalBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        CleanShotTheme.canvas(for: colorScheme)
            .ignoresSafeArea()
    }
}


struct HabitSidebar: View {
    let habits: [Habit]
    let todayKey: String
    let onToggle: (Habit) -> Void
    let onDelete: (Habit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's Habits")
                    .font(.title3.bold())
                Spacer()
                Text("\(habits.count) \(habits.count == 1 ? "habit" : "habits")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if habits.isEmpty {
                ContentUnavailableView(
                    "No habits yet",
                    systemImage: "checklist",
                    description: Text("Add a habit in the center panel to start tracking today.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(habits) { habit in
                            HabitCard(
                                habit: habit,
                                todayKey: todayKey,
                                onToggle: onToggle,
                                onDelete: onDelete
                            )
                        }
                    }
                    .padding(.bottom, 18)
                }
            }
        }
        .padding(18)
        .sidebarSurfaceStyle()
    }
}

struct HabitCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let habit: Habit
    let todayKey: String
    let onToggle: (Habit) -> Void
    let onDelete: (Habit) -> Void
    var cluster: AccountabilityDashboard.HabitTimeCluster? = nil
    var stampNamespace: Namespace.ID? = nil

    @State private var isHovered = false
    @State private var showArchiveConfirm = false

    private var doneToday: Bool { habit.completedDayKeys.contains(todayKey) }
    private var isHabitEntry: Bool { habit.entryType == .habit }
    private var currentStreak: Int { HabitMetrics.currentStreak(for: habit.completedDayKeys, endingAt: todayKey) }
    private var bestStreak: Int { HabitMetrics.bestStreak(for: habit.completedDayKeys) }
    private var recentDays: [DayInfo] { DateKey.recentDays(count: 7) }
    private var completionTint: Color {
        isHabitEntry ? CleanShotTheme.success : CleanShotTheme.accent
    }
    private var cardTint: Color {
        switch habit.entryType {
        case .task:
            return CleanShotTheme.accent.opacity(colorScheme == .dark ? 0.10 : 0.07)
        case .habit:
            return CleanShotTheme.success.opacity(colorScheme == .dark ? 0.10 : 0.07)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    onToggle(habit)
                }
            } label: {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(doneToday ? completionTint : .secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(habit.title)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough(doneToday)
                        .foregroundStyle(doneToday ? .secondary : .primary)
                        .lineLimit(1)
                    if isHabitEntry, let cluster, cluster.sampleSize >= 3 {
                        HabitClusterBadge(timeSlot: cluster.timeSlot)
                    }
                }

                HStack(spacing: 8) {
                    if isHabitEntry {
                        if currentStreak > 0 {
                            Label("\(currentStreak)d", systemImage: "flame.fill")
                                .foregroundStyle(CleanShotTheme.warning)
                        }
                        if bestStreak > 0 {
                            Label("\(bestStreak)d best", systemImage: "trophy.fill")
                                .foregroundStyle(CleanShotTheme.gold)
                        }
                    } else {
                        Label("Task", systemImage: "checklist")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 3) {
                        ForEach(recentDays) { day in
                            Circle()
                                .fill(
                                    habit.completedDayKeys.contains(day.key)
                                        ? completionTint
                                        : CleanShotTheme.controlFill(for: colorScheme)
                                )
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .font(.caption2.weight(.semibold))
            }

            Spacer(minLength: 4)

            SyncStatusBadge(status: habit.syncStatus)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 560, alignment: .leading)
        .background(cardTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .cleanShotSurface(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
            level: .control,
            isActive: isHovered
        )
        .scaleEffect(isHovered ? 1.008 : 1)
        .animation(.smooth(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .modifier(MatchedStampFrame(id: habit.persistentModelID, namespace: stampNamespace))
        .contextMenu {
            Button(role: .destructive) {
                showArchiveConfirm = true
            } label: {
                Label("Archive \(habit.entryType.title.lowercased())", systemImage: "archivebox")
            }
        }
        .confirmationDialog(
            "Archive \"\(habit.title)\"?",
            isPresented: $showArchiveConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    onDelete(habit)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your history will be preserved. Archived items can't be restored.")
        }
    }
}

// MARK: - Sync status badge

/// Compact indicator shown on a HabitCard when the local record diverges from the server.
/// Hidden entirely when synced so it consumes no layout space.
private struct SyncStatusBadge: View {
    let status: SyncStatus
    @State private var spinning = false

    var body: some View {
        Group {
            switch status {
            case .synced, .deleted:
                Color.clear.frame(width: 0, height: 0)
            case .pending:
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spinning)
                    .onAppear { spinning = true }
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .help("Sync failed — will retry on next sync")
            }
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.smooth(duration: 0.2), value: status)
    }
}

// MARK: - Matched-geometry helper

/// Opts the wrapped view into the shared stamp namespace when one is available,
/// so the HabitCard and the AmbientStamp for the same habit can interpolate
/// into each other on completion. When no namespace is threaded through, the
/// modifier is a no-op (e.g. HabitCard used inside HabitSidebar).
private struct MatchedStampFrame: ViewModifier {
    let id: PersistentIdentifier
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: true
            )
        } else {
            content
        }
    }
}

// MARK: - Ambient done-habit stamps

struct DoneHabitPillsBackground: View {
    let habits: [Habit]
    let todayKey: String
    var stampNamespace: Namespace.ID? = nil

    private static let noFlyCenterWidthRatio: CGFloat = 0.58
    private static let noFlyCenterHeightRatio: CGFloat = 0.62
    private static let minStampSeparation: CGFloat = 150
    private static let stampMarginX: CGFloat = 48
    private static let stampMarginY: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let layout = computeLayout(in: geo.size)
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(habits) { habit in
                        if let slot = layout[habit.persistentModelID] {
                            let xOff = cos(t * slot.speed * 0.55 + slot.phase) * slot.amp
                            let yOff = sin(t * slot.speed + slot.phase + 0.8) * slot.amp * 0.6
                            let tilt = slot.restAngle + sin(t * slot.speed * 0.25 + slot.phase) * 2.5
                            AmbientStamp(
                                habit: habit,
                                todayKey: todayKey,
                                accent: slot.accent,
                                scale: slot.scale,
                                stampNamespace: stampNamespace
                            )
                            .rotationEffect(.degrees(tilt))
                            .offset(x: xOff, y: yOff)
                            .position(x: slot.x, y: slot.y)
                            .transition(.opacity.combined(with: .scale(scale: 0.88)))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private struct Slot {
        let x, y: CGFloat
        let phase, speed, amp, restAngle: Double
        let accent: Color
        let scale: CGFloat
    }

    /// Greedy placement: for each stamp (stable order by createdAt) pick a seeded
    /// candidate, then nudge outward if it collides with an earlier stamp or
    /// intersects the central no-fly rect that the main list occupies.
    private func computeLayout(in size: CGSize) -> [PersistentIdentifier: Slot] {
        guard size.width > 0, size.height > 0, !habits.isEmpty else { return [:] }

        let ordered = habits.sorted { $0.createdAt < $1.createdAt }
        let noFly = CGRect(
            x: size.width * (1 - Self.noFlyCenterWidthRatio) / 2,
            y: size.height * (1 - Self.noFlyCenterHeightRatio) / 2,
            width: size.width * Self.noFlyCenterWidthRatio,
            height: size.height * Self.noFlyCenterHeightRatio
        )

        var placed: [CGPoint] = []
        var result: [PersistentIdentifier: Slot] = [:]

        for (index, habit) in ordered.enumerated() {
            let seed = habit.createdAt.timeIntervalSinceReferenceDate + Double(index) * 13.7
            let params = stampParams(seed: seed, habit: habit)
            let point = findCandidate(
                seed: seed,
                size: size,
                noFly: noFly,
                placed: placed
            )
            placed.append(point)
            result[habit.persistentModelID] = Slot(
                x: point.x,
                y: point.y,
                phase: params.phase,
                speed: params.speed,
                amp: params.amp,
                restAngle: params.restAngle,
                accent: params.accent,
                scale: params.scale
            )
        }
        return result
    }

    private struct StampParams {
        let phase, speed, amp, restAngle: Double
        let accent: Color
        let scale: CGFloat
    }

    private func stampParams(seed: Double, habit: Habit) -> StampParams {
        let r2 = fract(sin(seed * 451.3) * 75291.1)
        let r3 = fract(sin(seed * 211.9) * 58173.4)
        let r4 = fract(sin(seed * 173.3) * 64821.5)
        let r5 = fract(sin(seed * 397.7) * 81234.6)
        let r6 = fract(sin(seed * 523.1) * 37492.8)

        let accent: Color = (habit.entryType == .habit)
            ? CleanShotTheme.success
            : CleanShotTheme.accent

        return StampParams(
            phase:     r2 * .pi * 2,
            speed:     r3 * 0.13 + 0.07,
            amp:       r4 * 10 + 5,
            restAngle: r5 * 14 - 7,
            accent:    accent,
            scale:     CGFloat(r6 * 0.22 + 0.86)
        )
    }

    private func findCandidate(
        seed: Double,
        size: CGSize,
        noFly: CGRect,
        placed: [CGPoint]
    ) -> CGPoint {
        let minX = Self.stampMarginX
        let maxX = max(minX + 1, size.width - Self.stampMarginX)
        let minY = Self.stampMarginY
        let maxY = max(minY + 1, size.height - Self.stampMarginY)

        var best: CGPoint = CGPoint(x: minX, y: minY)
        var bestScore: CGFloat = -.infinity

        for attempt in 0..<28 {
            let sx = fract(sin(seed * (131.7 + Double(attempt) * 0.91)) * 67381.2)
            let sy = fract(sin(seed * (217.3 + Double(attempt) * 1.07)) * 54217.6)
            var candidate = CGPoint(
                x: CGFloat(sx) * (maxX - minX) + minX,
                y: CGFloat(sy) * (maxY - minY) + minY
            )

            if noFly.contains(candidate) {
                // Push candidate toward the nearest edge of the no-fly rect
                let dLeft = candidate.x - noFly.minX
                let dRight = noFly.maxX - candidate.x
                let dTop = candidate.y - noFly.minY
                let dBottom = noFly.maxY - candidate.y
                let minD = min(dLeft, dRight, dTop, dBottom)
                if minD == dLeft { candidate.x = noFly.minX - 24 }
                else if minD == dRight { candidate.x = noFly.maxX + 24 }
                else if minD == dTop { candidate.y = noFly.minY - 24 }
                else { candidate.y = noFly.maxY + 24 }
                candidate.x = min(max(candidate.x, minX), maxX)
                candidate.y = min(max(candidate.y, minY), maxY)
            }

            let nearest = placed.map { hypot(candidate.x - $0.x, candidate.y - $0.y) }.min() ?? .infinity
            if nearest >= Self.minStampSeparation { return candidate }
            if nearest > bestScore {
                bestScore = nearest
                best = candidate
            }
        }
        return best
    }

    private func fract(_ v: Double) -> Double { v - floor(v) }
}

private struct AmbientStamp: View {
    let habit: Habit
    let todayKey: String
    let accent: Color
    let scale: CGFloat
    var stampNamespace: Namespace.ID? = nil

    @State private var pulse = false

    private var recentDays: [DayInfo] {
        DateKey.recentDays(count: 7, endingAt: DateKey.date(from: todayKey))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 38, height: 38)
                Circle()
                    .strokeBorder(accent.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 38, height: 38)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
            }
            .scaleEffect(pulse ? 1.07 : 1.0)
            .animation(
                .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                value: pulse
            )

            Text(habit.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.70))
                .lineLimit(1)
                .frame(maxWidth: 80)

            HStack(spacing: 3) {
                ForEach(recentDays) { day in
                    Circle()
                        .fill(
                            habit.completedDayKeys.contains(day.key)
                                ? accent
                                : accent.opacity(0.18)
                        )
                        .frame(width: 4, height: 4)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(accent.opacity(0.07))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(0.55), accent.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.06), radius: 3,  x: 0, y: 1)
        .scaleEffect(scale)
        .opacity(0.82)
        .modifier(MatchedStampFrame(id: habit.persistentModelID, namespace: stampNamespace))
        .onAppear { pulse = true }
    }
}
