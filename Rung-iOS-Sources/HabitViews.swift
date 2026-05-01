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
    var hasOverdueTask: Bool = false
    var hasDuplicateEntry: Bool = false
    /// Optional backend store used for the LLM frequency-parse fallback.
    /// Nil disables the fallback — only the local regex pass runs.
    var backendStore: HabitBackendStore? = nil
    /// Commits a new habit / task. The trailing optionals carry any
    /// canonical-match + weekly-target selection collected by the
    /// confirmation card shown for habit-type adds. Tasks always pass nil
    /// for both.
    let onAddHabit: (HabitEntryType, Date?, CanonicalHabit?, Int?, TaskPriority?) -> Void

    @State private var isHovered = false
    @State private var showValidationError = false
    @State private var dueAt: Date? = nil
    @State private var showDuePicker = false
    @State private var taskPriority: TaskPriority? = nil
    /// True while the LLM frequency fallback is in flight. Keeps the user
    /// looking at a single "thinking" affordance instead of a flickering
    /// confirmation card that pops, then re-mutates a half-second later.
    @State private var isParsingWithAI = false
    @FocusState private var fieldFocused: Bool

    /// Populated once the user taps Add on a habit-type entry — surfaces an
    /// inline confirmation card so they can pick a weekly target and
    /// accept/decline any canonical HealthKit verification before the
    /// habit actually commits.
    @State private var pendingHabit: PendingHabitAdd?

    /// Triggered after committing a canonical "screenTime" habit on iOS so
    /// the user can nominate which apps count as social via Apple's
    /// `FamilyActivityPicker`. Only meaningful when Family Controls is
    /// authorized — the sheet itself handles the empty/cancel cases.
    #if os(iOS)
    @State private var showSocialAppsPicker = false
    #endif

    /// Frequency-picker options shown on the confirmation card. nil =
    /// daily; 7 isn't offered because it's the same commitment as Daily
    /// and would just confuse the perfect-day rest-budget math.
    private static let frequencyOptions: [Int?] = [nil, 3, 5]

    struct PendingHabitAdd: Equatable {
        let title: String
        let match: CanonicalHabit?
        var weeklyTarget: Int?
        var acceptCanonical: Bool
    }

    private var isBlockedByOverdue: Bool {
        selectedType == .task && hasOverdueTask
    }

    /// Only surface the duplicate warning once the user has typed something;
    /// otherwise the field is empty and there's nothing to dedupe against.
    private var isBlockedByDuplicate: Bool {
        hasDuplicateEntry && !newHabitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(placeholderText, text: $newHabitTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.leading, 16)
                    .focused($fieldFocused)
                    // Habits can't be renamed after creation, so surface
                    // autocorrect + sentence-case spell-check before the user
                    // commits to living with the spelling.
                    .autocorrectionDisabled(false)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                    .onChange(of: newHabitTitle) { _, _ in showValidationError = false }
                    .onSubmit(attemptAdd)

                if selectedType == .task {
                    DueDateControl(dueAt: $dueAt, isPresented: $showDuePicker)
                    PriorityControl(selection: $taskPriority)
                }

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
            .pressHover($isHovered)

            if isBlockedByOverdue {
                Label("Finish your overdue task before adding a new one.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(CleanShotTheme.danger)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            } else if isBlockedByDuplicate {
                Label(duplicateWarningText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(CleanShotTheme.danger)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            } else if showValidationError {
                Text("Give your \(selectedType.title.lowercased()) a real name — something you'd actually say out loud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }

            // Sleep-derived best-time hint, shown only when the user is
            // typing a habit (tasks have due dates instead) and our HK
            // pull has produced a snapshot. Renders nothing otherwise so
            // the layout doesn't jump for users without sleep data.
            if selectedType == .habit && pendingHabit == nil && !newHabitTitle.isEmpty {
                SleepSuggestionChip(
                    service: SleepInsightsService.shared,
                    habitTitle: newHabitTitle
                )
                .padding(.leading, 16)
            }

            if let pending = pendingHabit {
                habitConfirmCard(pending: pending)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showValidationError)
        .animation(.easeOut(duration: 0.2), value: isBlockedByOverdue)
        .animation(.easeOut(duration: 0.2), value: isBlockedByDuplicate)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: pendingHabit)
        .task { await SleepInsightsService.shared.refresh() }
        #if os(iOS)
        .sheet(isPresented: $showSocialAppsPicker) {
            SocialAppsPickerSheet(isPresented: $showSocialAppsPicker)
        }
        #endif
    }

    /// Inline confirmation card shown after the user taps Add on a habit.
    /// Gives them one chance to (a) pick a weekly target so frequency
    /// habits like "gym 5×/week" drop out of the list once met, and
    /// (b) accept or decline the canonical HealthKit verification
    /// suggestion — we never apply it silently.
    private func habitConfirmCard(pending: PendingHabitAdd) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CleanShotTheme.success)
                Text(pending.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("How often?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Self.frequencyOptions, id: \.self) { option in
                        frequencyPill(option: option, selected: pending.weeklyTarget)
                    }
                }
            }

            if let match = pending.match {
                HStack(spacing: 10) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Verify with Apple Health")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Tracks as \(match.displayName) · \(tierLabel(match.tier))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { pending.acceptCanonical },
                            set: { newValue in
                                guard var updated = pendingHabit else { return }
                                updated.acceptCanonical = newValue
                                pendingHabit = updated
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.pink.opacity(0.08))
                )
            }

            HStack(spacing: 8) {
                Button {
                    pendingHabit = nil
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    commitPending()
                } label: {
                    Text("Add habit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(Capsule().fill(CleanShotTheme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CleanShotTheme.accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CleanShotTheme.accent.opacity(0.22), lineWidth: 0.75)
        )
    }

    private func frequencyPill(option: Int?, selected: Int?) -> some View {
        let isActive = option == selected
        let label: String = option.map { "\($0)×/wk" } ?? "Daily"
        return Button {
            guard var updated = pendingHabit else { return }
            updated.weeklyTarget = option
            pendingHabit = updated
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? .white : .primary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    Capsule()
                        .fill(isActive ? CleanShotTheme.accent : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    private func tierLabel(_ tier: VerificationTier) -> String {
        switch tier {
        case .auto: return "HealthKit verified"
        case .partial: return "Partially verified"
        case .selfReport: return "Self-reported"
        }
    }

    private func commitPending() {
        guard let pending = pendingHabit else { return }
        let canonical = pending.acceptCanonical ? pending.match : nil
        onAddHabit(.habit, nil, canonical, pending.weeklyTarget, nil)
        let needsSocialPicker = canonical?.key == "screenTime"
        pendingHabit = nil
        #if os(iOS)
        // The screenTime canonical can only verify against an explicit
        // app list — without picking the apps the monitor has nothing to
        // count, so we surface the picker right after commit.
        if needsSocialPicker { showSocialAppsPicker = true }
        #else
        _ = needsSocialPicker  // silence unused-let warning on macOS
        #endif
    }

    private var duplicateWarningText: String {
        switch selectedType {
        case .habit: return "You already have a habit with this name."
        case .task:  return "You already have a pending task with this name."
        }
    }

    private var placeholderText: String {
        "Add a new \(selectedType.title.lowercased())..."
    }

    private func attemptAdd() {
        guard !isBlockedByOverdue else { return }
        guard !isBlockedByDuplicate else { return }
        guard isLikelyMeaningful(newHabitTitle) else {
            withAnimation { showValidationError = true }
            return
        }
        showValidationError = false
        let trimmed = newHabitTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // Tasks commit straight through — no verification or weekly target.
        if selectedType == .task {
            onAddHabit(.task, dueAt, nil, nil, taskPriority)
            dueAt = nil
            taskPriority = nil
            return
        }

        // Habits drop into the inline confirmation card so the user can
        // pick a weekly frequency and opt in/out of the canonical
        // HealthKit verification (never auto-applied silently). If the
        // user already encoded a frequency in the title ("gym 4 days a
        // week"), the parser pre-fills the matching pill and drops the
        // clause from the title — they can still override either choice.
        let parsed = FrequencyParser.parse(trimmed)

        if parsed.didMatch {
            applyParseResult(parsed, fallbackText: trimmed)
            return
        }

        // Regex didn't catch it — try the backend LLM fallback if the user
        // gave us a real hint (numbers / "week" / "day" / etc) AND we have
        // an authenticated session. Otherwise skip straight to the card.
        if let store = backendStore, FrequencyParser.hasFrequencyHint(trimmed) {
            isParsingWithAI = true
            fieldFocused = false
            Task {
                let aiResult = await store.parseHabitFrequencyWithAI(text: trimmed)
                await MainActor.run {
                    isParsingWithAI = false
                    if let aiResult, aiResult.didMatch, !aiResult.cleanedTitle.isEmpty {
                        let synthesised = FrequencyParser.ParseResult(
                            cleanedTitle: aiResult.cleanedTitle,
                            weeklyTarget: aiResult.weeklyTarget,
                            didMatch: true
                        )
                        applyParseResult(synthesised, fallbackText: trimmed)
                    } else {
                        applyParseResult(.empty, fallbackText: trimmed)
                    }
                }
            }
            return
        }

        applyParseResult(.empty, fallbackText: trimmed)
    }

    /// Assemble the inline confirmation card from a parse result. Treats
    /// `result.didMatch == false` as "use the user's untouched input" so
    /// the LLM-miss path collapses into the original behaviour.
    private func applyParseResult(_ result: FrequencyParser.ParseResult, fallbackText: String) {
        let workingTitle = result.didMatch && !result.cleanedTitle.isEmpty
            ? result.cleanedTitle
            : fallbackText
        let presetTarget = result.didMatch ? snapWeeklyTarget(result.weeklyTarget) : nil
        let match = CanonicalHabits.match(userTitle: workingTitle)
        pendingHabit = PendingHabitAdd(
            title: workingTitle,
            match: match,
            weeklyTarget: presetTarget,
            acceptCanonical: match != nil
        )
        fieldFocused = false
    }

    /// The confirmation card only offers nil / 3 / 5 today, so a parser hit
    /// of "gym 4 days a week" would otherwise show no selected pill. Snap
    /// to the closest offered value so the user sees a real preselection
    /// (and can adjust freely from there). 7 → daily (nil) so the daily pill
    /// lights up instead of forcing a synthetic 7-pill.
    private func snapWeeklyTarget(_ raw: Int?) -> Int? {
        guard let raw else { return nil }
        if raw >= 7 { return nil }
        if raw >= 5 { return 5 }
        return 3
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
                    if selection != option { Haptics.selection() }
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

/// Three-bucket task priority picker that lives in `AddHabitBar` next to
/// the due-date control. Tapping cycles through `low → medium → high → none`
/// so the entire interaction is one finger and zero modal sheets.
private struct PriorityControl: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: TaskPriority?

    @State private var isHovered = false

    var body: some View {
        Button(action: cycle) {
            trigger
        }
        .buttonStyle(.plain)
        .pressHover($isHovered)
        .help(selection == nil ? "Set priority" : "Priority: \(selection?.label ?? "")")
        .accessibilityLabel("Task priority")
        .accessibilityValue(selection?.label ?? "None")
    }

    private func cycle() {
        Haptics.selection()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            switch selection {
            case nil:        selection = .low
            case .low:       selection = .medium
            case .medium:    selection = .high
            case .high:      selection = nil
            }
        }
    }

    @ViewBuilder
    private var trigger: some View {
        if let p = selection {
            HStack(spacing: 5) {
                Image(systemName: p.systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(p.label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(tint(for: p))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(tint(for: p).opacity(colorScheme == .dark ? 0.18 : 0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint(for: p).opacity(0.28), lineWidth: 0.5)
            )
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        } else {
            Image(systemName: "flag")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
    }

    private func tint(for p: TaskPriority) -> Color {
        switch p {
        case .low:    return .blue
        case .medium: return .orange
        case .high:   return .red
        }
    }
}

private struct DueDateControl: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var dueAt: Date?
    @Binding var isPresented: Bool

    @State private var isHovered = false

    var body: some View {
        Button {
            #if os(iOS)
            // The due-date picker sits next to the add-task text field, which
            // owns the software keyboard. Resign it before we present so the
            // picker isn't squeezed into a 200pt strip above the keyboard.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
            #endif
            isPresented = true
        } label: {
            trigger
        }
        .buttonStyle(.plain)
        .pressHover($isHovered)
        .help(dueAt == nil ? "Set a due date (optional)" : "Change due date")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DueDatePopover(
                dueAt: $dueAt,
                isPresented: $isPresented
            )
            #if os(iOS)
            // Present as a sheet on iPhone with detents so the calendar is
            // always fully visible and cooperates with the keyboard. The
            // previous `.popover` adaptation crammed everything into a tiny
            // popup that clipped the "Other" calendar and the Done button.
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCompactAdaptation(.sheet)
            #endif
        }
    }

    @ViewBuilder
    private var trigger: some View {
        if let dueAt {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .bold))
                Text(DueDateFormat.relative(dueAt))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(CleanShotTheme.accent)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(CleanShotTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(CleanShotTheme.accent.opacity(0.28), lineWidth: 0.5)
            )
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        } else {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
    }
}

private struct DueDatePopover: View {
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
    private var isCompact: Bool { false }
    #endif
    @Binding var dueAt: Date?
    @Binding var isPresented: Bool

    @State private var draft: Date
    @State private var showsCustomCalendar = false

    init(dueAt: Binding<Date?>, isPresented: Binding<Bool>) {
        self._dueAt = dueAt
        self._isPresented = isPresented
        let seed = dueAt.wrappedValue
            ?? Calendar.current.startOfDay(for: Date())
        self._draft = State(initialValue: seed)
    }

    private var presets: [DueDatePreset] { DueDatePreset.defaults }
    private var activePreset: DueDatePreset? {
        presets.first { Calendar.current.isDate($0.date, inSameDayAs: draft) }
    }
    private var selectedDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: draft)
    }
    private var isOtherSelected: Bool { activePreset == nil }

    var body: some View {
        Group {
            if isCompact {
                // Sheet layout on iPhone: the sheet supplies the rounded
                // material background and drag handle, so we skip the custom
                // popover chrome and wrap the content in a ScrollView so the
                // "Other" calendar + action bar always stay reachable.
                ScrollView {
                    mainContent
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
            } else {
                mainContent
                    .frame(width: 328)
                    .padding(.top, 2)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(CleanShotTheme.stroke(for: colorScheme), lineWidth: 1)
                    )
            }
        }
        .animation(.smooth(duration: 0.18), value: showsCustomCalendar)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Due Date")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.65)

                Text(selectedDateText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(presets) { preset in
                    presetButton(preset)
                }
                otherButton
            }
            .padding(.horizontal, 12)

            if showsCustomCalendar {
                DueDateCalendarGrid(draft: $draft)
                    .padding(.horizontal, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack {
                if dueAt != nil {
                    Button {
                        withAnimation(.smooth(duration: 0.15)) {
                            dueAt = nil
                        }
                        isPresented = false
                    } label: {
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CleanShotTheme.danger)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CleanShotTheme.controlFill(for: colorScheme))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    dueAt = Calendar.current.startOfDay(for: draft)
                    isPresented = false
                } label: {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule(style: .continuous).fill(CleanShotTheme.accent))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func presetButton(_ preset: DueDatePreset) -> some View {
        let isActive = activePreset?.id == preset.id
        return Button {
            withAnimation(.smooth(duration: 0.15)) {
                draft = preset.date
                showsCustomCalendar = false
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: preset.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(preset.label)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text(preset.shortDate)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(isActive ? CleanShotTheme.accent : .primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isActive
                            ? CleanShotTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.12)
                            : CleanShotTheme.controlFill(for: colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isActive ? CleanShotTheme.accent.opacity(0.30) : Color.clear,
                        lineWidth: 0.75
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var otherButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.18)) {
                showsCustomCalendar = true
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                Text("Other")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                if isOtherSelected {
                    Text("Custom")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isOtherSelected || showsCustomCalendar ? CleanShotTheme.accent : .primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        (isOtherSelected || showsCustomCalendar)
                            ? CleanShotTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.12)
                            : CleanShotTheme.controlFill(for: colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        (isOtherSelected || showsCustomCalendar) ? CleanShotTheme.accent.opacity(0.30) : Color.clear,
                        lineWidth: 0.75
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DueDateCalendarGrid: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var draft: Date
    @State private var visibleMonth: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    init(draft: Binding<Date>) {
        self._draft = draft
        self._visibleMonth = State(initialValue: Self.startOfMonth(for: draft.wrappedValue))
    }

    private var calendar: Calendar { Calendar.current }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: visibleMonth)
    }

    private var weekdaySymbols: [String] {
        let symbols = DateFormatter().veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let firstIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[firstIndex..<symbols.count]) + Array(symbols[0..<firstIndex])
    }

    private var monthDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: visibleMonth)
        let leadingEmptyDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days = Array<Date?>(repeating: nil, count: leadingEmptyDays)

        for day in range {
            var components = calendar.dateComponents([.year, .month], from: visibleMonth)
            components.day = day
            days.append(calendar.date(from: components).map { calendar.startOfDay(for: $0) })
        }

        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                monthButton(systemImage: "chevron.left") {
                    moveMonth(by: -1)
                }

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                monthButton(systemImage: "chevron.right") {
                    moveMonth(by: 1)
                }
            }

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 18)
                }

                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayButton(for: date)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CleanShotTheme.controlFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CleanShotTheme.stroke(for: colorScheme), lineWidth: 0.75)
        )
        .onChange(of: draft) { _, newValue in
            let month = Self.startOfMonth(for: newValue)
            if !calendar.isDate(month, equalTo: visibleMonth, toGranularity: .month) {
                visibleMonth = month
            }
        }
    }

    private func monthButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(CleanShotTheme.controlFill(for: colorScheme))
                )
        }
        .buttonStyle(.plain)
    }

    private func dayButton(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: draft)
        let isToday = calendar.isDateInToday(date)

        return Button {
            withAnimation(.smooth(duration: 0.12)) {
                draft = calendar.startOfDay(for: date)
            }
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(dayForeground(isSelected: isSelected, isToday: isToday))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? CleanShotTheme.accent : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isToday && !isSelected ? CleanShotTheme.accent.opacity(0.55) : Color.clear, lineWidth: 0.75)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayForeground(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return CleanShotTheme.accent }
        return .primary
    }

    private func moveMonth(by amount: Int) {
        withAnimation(.smooth(duration: 0.14)) {
            visibleMonth = calendar.date(byAdding: .month, value: amount, to: visibleMonth) ?? visibleMonth
        }
    }

    private static func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}

private struct DueDatePreset: Identifiable {
    let id: String
    let label: String
    let icon: String
    let date: Date

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    static var defaults: [DueDatePreset] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today

        // Next Saturday (weekend)
        let weekday = cal.component(.weekday, from: today)
        let daysToSaturday = (7 - weekday) % 7 // Sat = 7
        let saturdayOffset = daysToSaturday == 0 ? 7 : daysToSaturday
        let weekend = cal.date(byAdding: .day, value: saturdayOffset, to: today) ?? today

        let nextWeek = cal.date(byAdding: .day, value: 7, to: today) ?? today

        return [
            .init(id: "today", label: "Today", icon: "sun.max.fill", date: today),
            .init(id: "tomorrow", label: "Tomorrow", icon: "sunrise.fill", date: tomorrow),
            .init(id: "weekend", label: "Weekend", icon: "sparkles", date: weekend),
            .init(id: "nextweek", label: "Next week", icon: "arrow.forward.circle.fill", date: nextWeek)
        ]
    }
}

enum DueDateFormat {
    static func relative(_ date: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: today, to: target).day ?? 0

        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6:
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
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
    var isFrozenToday: Bool = false

    /// Pulled once per list refresh. Per-habit slices feed each card's
    /// timing-stats pill. SwiftData diffs efficiently so this stays cheap
    /// even as the completion table grows.
    @Query private var allCompletions: [HabitCompletion]

    private var doneCount: Int {
        habits.filter { $0.completedDayKeys.contains(todayKey) }.count
    }

    /// Per-habit timing stats keyed by `habit.localUUID`. Computed once
    /// per render from the SwiftData @Query. Habits without a localUUID
    /// (legacy rows that haven't been touched yet) get `.empty`.
    private var statsByHabit: [UUID: HabitTimingStats] {
        let grouped = HabitTimingStatsCalculator.groupByHabitLocalId(allCompletions)
        var out: [UUID: HabitTimingStats] = [:]
        for (id, slice) in grouped {
            out[id] = HabitTimingStatsCalculator.compute(from: slice)
        }
        return out
    }

    /// Tasks float ahead of habits and are ordered high→medium→low→none by
    /// priority; habits keep their original order. Within a priority bucket,
    /// older items come first so the user's existing commitments stay above
    /// later additions.
    private var orderedHabits: [Habit] {
        let tasks = habits
            .filter { $0.entryType == .task }
            .sorted { a, b in
                let aw = a.priority?.sortWeight ?? 0
                let bw = b.priority?.sortWeight ?? 0
                if aw != bw { return aw > bw }
                return a.createdAt < b.createdAt
            }
        let habitsOnly = habits.filter { $0.entryType == .habit }
        return tasks + habitsOnly
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
                if isFrozenToday {
                    Label("Frozen", systemImage: "snowflake")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.cyan)
                } else {
                    Text("\(doneCount)/\(habits.count) done")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 4)

            LazyVStack(spacing: 6) {
                ForEach(orderedHabits) { habit in
                    HabitCard(
                        habit: habit,
                        todayKey: todayKey,
                        onToggle: onToggle,
                        onDelete: onDelete,
                        cluster: cluster(for: habit),
                        stampNamespace: stampNamespace,
                        isFrozen: isFrozenToday,
                        timingStats: habit.localUUID.flatMap { statsByHabit[$0] }
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct HabitCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [PersistentIdentifier: CGRect] = [:]

    static func reduce(
        value: inout [PersistentIdentifier: CGRect],
        nextValue: () -> [PersistentIdentifier: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
    var reportsFrame: Bool = true
    /// Today is protected by a streak freeze. Overrides the normal check state
    /// visually (icy-blue, snowflake) without mutating the underlying
    /// `completedDayKeys` — local metrics remain the source of truth.
    var isFrozen: Bool = false
    /// Per-habit "usually 7:42 AM · 18 min" rollup, computed by the parent
    /// from `[HabitCompletion]`. Nil for habits without enough samples.
    var timingStats: HabitTimingStats? = nil

    @State private var isHovered = false
    @State private var showArchiveConfirm = false
    @State private var showDeleteConfirm = false

    private var doneToday: Bool {
        switch habit.entryType {
        case .habit: return habit.completedDayKeys.contains(todayKey)
        case .task:  return habit.isTaskCompleted
        }
    }
    private var effectiveDone: Bool { isFrozen || doneToday }
    private var isHabitEntry: Bool { habit.entryType == .habit }
    private var isAutoVerified: Bool { habit.isAutoVerified }
    private var isOverdue: Bool { habit.isOverdue() }
    /// iPad reads HealthKit only via iCloud Health sync (when enabled) and
    /// has NO background HKObserver delivery — the verifier only fires
    /// when the app is foregrounded, and Screen Time only sees iPad usage.
    /// In practice, the iPhone is the device that actually completes
    /// auto-verified habits, so iPad mirrors the macOS copy ("Auto-checks
    /// on iPhone") and hides the manual-override item.
    private var renderAsRemoteVerifyDevice: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }
    private var currentStreak: Int { HabitMetrics.currentStreak(for: habit.completedDayKeys, endingAt: todayKey) }
    private var bestStreak: Int { HabitMetrics.bestStreak(for: habit.completedDayKeys) }
    private var recentDays: [DayInfo] { DateKey.recentDays(count: 7) }
    private var completionTint: Color {
        if isFrozen { return Color.cyan }
        if isAutoVerified { return Color.pink }
        if isHabitEntry { return CleanShotTheme.success }
        return isOverdue ? CleanShotTheme.danger : CleanShotTheme.accent
    }
    /// Status copy shown beneath the title for auto-verified habits so
    /// the user understands why the circle isn't tappable. Empty for
    /// manual habits — they fall back to the streak-flame label row.
    private var autoVerifyStatus: String? {
        guard isAutoVerified else { return nil }
        if doneToday { return "Verified by Apple Health" }
        if renderAsRemoteVerifyDevice {
            // iPad: the iPhone is the practical verifier — copy mirrors macOS.
            if habit.verificationSource == .screenTimeSocial {
                return "Auto-checks on iPhone (Screen Time)"
            }
            return "Auto-checks on iPhone (Apple Health)"
        }
        if habit.verificationSource == .screenTimeSocial {
            return "Waiting for Screen Time"
        }
        return "Waiting for Apple Health"
    }
    private var cardTint: Color {
        let opacity = colorScheme == .dark ? 0.10 : 0.07
        if isFrozen {
            return Color.cyan.opacity(opacity + 0.02)
        }
        switch habit.entryType {
        case .task:
            return (isOverdue ? CleanShotTheme.danger : CleanShotTheme.accent).opacity(opacity)
        case .habit:
            return CleanShotTheme.success.opacity(opacity)
        }
    }
    private var dueDateText: String? {
        guard habit.entryType == .task, let due = habit.dueAt else { return nil }
        return DueDateFormat.relative(due)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Auto-verified habits render a non-tappable indicator —
            // mistaken taps are silently ignored. The user can still
            // long-press the row to surface the manual override item in
            // the context menu when the evidence really is missing.
            Button {
                guard !isAutoVerified else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    onToggle(habit)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(effectiveDone ? completionTint.opacity(0.16) : Color.clear)
                    if isAutoVerified && !effectiveDone {
                        // Dashed border telegraphs "this fills itself" so
                        // users don't expect a tap to do anything.
                        Circle()
                            .strokeBorder(
                                Color.pink.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                            )
                    } else {
                        Circle()
                            .strokeBorder(
                                effectiveDone ? Color.clear : Color.secondary.opacity(0.32),
                                lineWidth: 1.5
                            )
                    }
                    if effectiveDone {
                        Image(systemName: isFrozen ? "snowflake" : (isAutoVerified ? "heart.fill" : "checkmark"))
                            .font(.system(size: isFrozen ? 12 : 11, weight: .bold))
                            .foregroundStyle(completionTint)
                            .contentTransition(.symbolEffect(.replace.downUp))
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    } else if isAutoVerified {
                        Image(systemName: "heart")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.pink.opacity(0.7))
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isAutoVerified
                    ? (doneToday ? "Verified by Apple Health" : "Waiting for Apple Health")
                    : (isFrozen ? "Frozen" : (doneToday ? "Done" : "Not done"))
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(habit.title)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough(effectiveDone)
                        .foregroundStyle(effectiveDone ? .secondary : .primary)
                        .lineLimit(1)
                    if !effectiveDone, habit.entryType == .task, let priority = habit.priority {
                        PriorityBadge(priority: priority)
                    }
                    if isAutoVerified && renderAsRemoteVerifyDevice {
                        HealthKitPill(source: habit.verificationSource)
                    }
                    if isHabitEntry, let cluster, cluster.sampleSize >= 3 {
                        HabitClusterBadge(timeSlot: cluster.timeSlot)
                    }
                }

                HStack(spacing: 8) {
                    if isHabitEntry {
                        if let status = autoVerifyStatus {
                            // Replaces the flame/trophy labels for
                            // auto-verified habits — the circle's
                            // appearance already carries the streak
                            // meaning and we don't want users to think
                            // they earned the streak by tapping.
                            Label(status, systemImage: "heart.text.square.fill")
                                .foregroundStyle(Color.pink.opacity(0.85))
                        } else {
                            if currentStreak > 0 {
                                Label("\(currentStreak)d", systemImage: "flame.fill")
                                    .foregroundStyle(CleanShotTheme.warning)
                            }
                            if bestStreak > 0 {
                                Label("\(bestStreak)d best", systemImage: "trophy.fill")
                                    .foregroundStyle(CleanShotTheme.gold)
                            }
                        }
                    } else {
                        if let dueDateText {
                            Label(dueDateText, systemImage: "calendar")
                                .foregroundStyle(isOverdue ? CleanShotTheme.danger : .secondary)
                        } else {
                            Label("Task", systemImage: "checklist")
                                .foregroundStyle(.secondary)
                        }
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

                // "Usually 7:42 AM · 18 min · ▼12% faster" — only renders
                // when the parent passed timing stats AND there's at least
                // one populated field. Hidden on auto-verified habits to
                // avoid stacking metadata under the existing pink status.
                if let timingStats, timingStats.isPresentable, !isAutoVerified {
                    HabitTimingStatsPill(stats: timingStats)
                }
            }

            Spacer(minLength: 4)

            SyncStatusBadge(status: habit.syncStatus)

            if !isHabitEntry {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete task")
                .help("Delete task")
            }
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
        .pressHover($isHovered)
        .modifier(MatchedStampFrame(id: habit.persistentModelID, namespace: stampNamespace))
        .background {
            if reportsFrame {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HabitCardFramePreferenceKey.self,
                        value: [habit.persistentModelID: proxy.frame(in: .global)]
                    )
                }
            }
        }
        .contextMenu {
            // Focus mode is available for any uncompleted item — both
            // tasks and habits benefit from a 25-minute lock-in. Sits at
            // the top of the menu so it's the most discoverable action.
            if !effectiveDone {
                Button {
                    FocusController.shared.start(taskTitle: habit.title)
                } label: {
                    Label("Start focus session", systemImage: "timer")
                }
            }
            if isHabitEntry {
                // Manual override is iPhone-only — iPad's HealthKit access is
                // background-disabled and Screen Time only sees iPad usage,
                // so the iPhone is the device that should record completions.
                if isAutoVerified && !doneToday && !renderAsRemoteVerifyDevice {
                    Button {
                        Task {
                            await AutoVerificationCoordinator.shared.manualOverride(
                                habit: habit, dayKey: todayKey
                            )
                        }
                    } label: {
                        Label("Mark done manually", systemImage: "checkmark.circle.dotted")
                    }
                }
                Button(role: .destructive) {
                    showArchiveConfirm = true
                } label: {
                    Label("Archive habit", systemImage: "archivebox")
                }
            } else {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete task", systemImage: "xmark")
                }
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
        .confirmationDialog(
            "Delete \"\(habit.title)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Task", role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    onDelete(habit)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This task will be removed from your list.")
        }
    }
}

// MARK: - Sync status badge

/// Compact indicator shown on a HabitCard when the local record diverges from the server.
/// Hidden entirely when synced so it consumes no layout space.
/// Inline rollup pill rendered under the streak label: "Usually 7:42 AM ·
/// 18 min · ▼ 12% faster". Each segment is conditional so a habit with
/// only a time-of-day median doesn't show empty separators. Tinted to
/// indigo (matches the SleepSuggestionChip palette) so the user
/// associates it with system-derived insights.
private struct HabitTimingStatsPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let stats: HabitTimingStats

    var body: some View {
        let segments = orderedSegments
        if segments.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 8, weight: .bold))
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                    }
                    Text(segment.text)
                        .foregroundStyle(segment.tint ?? Color.indigo)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.indigo)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.indigo.opacity(colorScheme == .dark ? 0.16 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.indigo.opacity(0.22), lineWidth: 0.5)
            )
            .accessibilityLabel(accessibilityCopy)
        }
    }

    private struct Segment {
        let text: String
        let tint: Color?
    }

    private var orderedSegments: [Segment] {
        var out: [Segment] = []
        if let label = stats.medianTimeOfDayLabel {
            out.append(Segment(text: "Usually \(label)", tint: nil))
        }
        if let label = stats.medianDurationLabel {
            out.append(Segment(text: label, tint: nil))
        }
        if let label = stats.speedDeltaLabel {
            // Tint speed deltas so faster reads green, slower reads orange.
            let isFaster = (stats.speedDeltaPercent ?? 0) < 0
            out.append(Segment(text: label, tint: isFaster ? .green : .orange))
        }
        return out
    }

    private var accessibilityCopy: String {
        orderedSegments.map(\.text).joined(separator: ", ")
    }
}

/// Subtle pill rendered next to a task's title showing its priority. Hidden
/// once the task is marked done so completed work doesn't keep shouting
/// for attention. Color-codes by urgency: blue (low), orange (medium),
/// red (high).
private struct PriorityBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let priority: TaskPriority

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: priority.systemImage)
                .font(.system(size: 8, weight: .bold))
            Text(priority.label)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.5)
        )
        .accessibilityLabel("Priority: \(priority.label)")
    }

    private var tint: Color {
        switch priority {
        case .low:    return .blue
        case .medium: return .orange
        case .high:   return .red
        }
    }
}

/// Pill rendered next to the habit title for auto-verified habits on devices
/// that don't actually run the verifier (iPad, macOS) — tells the user which
/// engine owns this habit's completion. iPhone keeps the existing pink
/// dashed circle + "Waiting for Apple Health" subtitle since it's the device
/// that actually fires the auto-check.
private struct HealthKitPill: View {
    let source: VerificationSource?

    private var label: String {
        if source == .screenTimeSocial { return "Screen Time" }
        return "Apple Health"
    }
    private var symbol: String {
        if source == .screenTimeSocial { return "iphone" }
        return "heart.fill"
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Color.pink)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.pink.opacity(0.12), in: Capsule())
    }
}

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
    var stampScaleMultiplier: CGFloat = 1
    var hiddenStampIds: Set<PersistentIdentifier> = []
    var compactMaxStamps: Int = 4

    private static let noFlyCenterWidthRatio: CGFloat = 0.58
    private static let noFlyCenterHeightRatio: CGFloat = 0.62
    private static let minStampSeparation: CGFloat = 150
    private static let stampMarginX: CGFloat = 48
    private static let stampMarginY: CGFloat = 56
    private static let stampNaturalSize = CGSize(width: 106, height: 88)
    private static let stampViewportPadding: CGFloat = 8

    // Caching the layout size keeps the stamps from reshuffling when the
    // keyboard slides up and shrinks the view height. We only refresh the
    // cache on width changes (rotation / window resize) — a height-only
    // change is essentially always the software keyboard. We can't use
    // `.ignoresSafeArea(.keyboard)` here because that shifts the view into
    // a different coordinate space from the HabitCard source, which breaks
    // the matchedGeometry morph when a habit is checked off.
    @State private var cachedSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let sizeToUse = cachedSize == .zero ? geo.size : cachedSize
            let layout = computeLayout(in: sizeToUse)
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(habits) { habit in
                        if let slot = layout[habit.persistentModelID] {
                            let isHidden = hiddenStampIds.contains(habit.persistentModelID)
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
                            .opacity(isHidden ? 0 : 1)
                            .transition(.opacity.combined(with: .scale(scale: 0.88)))
                        }
                    }
                }
            }
            .onAppear {
                if cachedSize == .zero { cachedSize = geo.size }
            }
            .onChange(of: geo.size.width) { _, _ in
                // Width-only update fires on rotation / window resize —
                // both cases where we *do* want a fresh layout. Height-only
                // changes (keyboard) are intentionally ignored.
                cachedSize = geo.size
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

    static func flightDestination(
        for habit: Habit,
        among habits: [Habit],
        in size: CGSize,
        stampScaleMultiplier: CGFloat,
        compactMaxStamps: Int = 4
    ) -> (point: CGPoint, accent: Color, scale: CGFloat)? {
        let layout = DoneHabitPillsBackground(
            habits: habits,
            todayKey: "",
            stampScaleMultiplier: stampScaleMultiplier,
            compactMaxStamps: compactMaxStamps
        ).computeLayout(in: size)
        guard let slot = layout[habit.persistentModelID] else { return nil }
        return (CGPoint(x: slot.x, y: slot.y), slot.accent, slot.scale)
    }

    /// Greedy placement: for each stamp (stable order by createdAt) pick a seeded
    /// candidate, then nudge outward if it collides with an earlier stamp or
    /// intersects the central no-fly rect that the main list occupies.
    private func computeLayout(in size: CGSize) -> [PersistentIdentifier: Slot] {
        guard size.width > 0, size.height > 0, !habits.isEmpty else { return [:] }

        let narrow = size.width < 500
        // On narrow screens the middle of the layout is occupied edge-to-edge by
        // the habit list / input card — leave only thin strips at the very top
        // and very bottom for ambient stamps. The cap is configurable because
        // iPhone uses smaller stamps and must keep newly completed items visible.
        let widthRatio: CGFloat = narrow ? 0.96 : Self.noFlyCenterWidthRatio
        let heightRatio: CGFloat = narrow ? 0.62 : Self.noFlyCenterHeightRatio

        let sortedHabits = habits.sorted { $0.createdAt < $1.createdAt }
        let ordered = narrow ? Array(sortedHabits.prefix(compactMaxStamps)) : sortedHabits
        let noFly = CGRect(
            x: size.width * (1 - widthRatio) / 2,
            y: size.height * (1 - heightRatio) / 2,
            width: size.width * widthRatio,
            height: size.height * heightRatio
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
                placed: placed,
                params: params
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
                scale: params.scale * stampScaleMultiplier
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
        placed: [CGPoint],
        params: StampParams
    ) -> CGPoint {
        let narrow = size.width < 500
        let floatPadding = CGFloat(params.amp) + Self.stampViewportPadding
        let effectiveScale = params.scale * stampScaleMultiplier
        let visibleMarginX = (Self.stampNaturalSize.width * effectiveScale / 2) + floatPadding
        let visibleMarginY = (Self.stampNaturalSize.height * effectiveScale / 2) + floatPadding
        let marginX = min(max(narrow ? 14 : Self.stampMarginX, visibleMarginX), size.width / 2)
        let marginY = min(max(narrow ? 40 : Self.stampMarginY, visibleMarginY), size.height / 2)
        let pushDistance = max(narrow ? 60 : 24, visibleMarginY)

        let minX = marginX
        let maxX = max(minX, size.width - marginX)
        let minY = marginY
        let maxY = max(minY, size.height - marginY)

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
                if narrow {
                    // Narrow screens have nearly-full-width no-fly (no left/right
                    // slivers to speak of) — pick the nearer of the top/bottom
                    // strips and re-seed y within that strip so the stamps
                    // spread rather than stacking at the strip boundary.
                    let ry = fract(sin(seed * (917.3 + Double(attempt) * 3.1)) * 28417.9)
                    let topMaxY = min(max(minY, noFly.minY - pushDistance), maxY)
                    let botMinY = max(min(maxY, noFly.maxY + pushDistance), minY)
                    if candidate.y - noFly.minY <= noFly.maxY - candidate.y {
                        candidate.y = CGFloat(ry) * (topMaxY - minY) + minY
                    } else {
                        candidate.y = CGFloat(ry) * (maxY - botMinY) + botMinY
                    }
                } else {
                    // Push candidate toward the nearest edge of the no-fly rect
                    let dLeft = candidate.x - noFly.minX
                    let dRight = noFly.maxX - candidate.x
                    let dTop = candidate.y - noFly.minY
                    let dBottom = noFly.maxY - candidate.y
                    let minD = min(dLeft, dRight, dTop, dBottom)
                    if minD == dLeft { candidate.x = noFly.minX - pushDistance }
                    else if minD == dRight { candidate.x = noFly.maxX + pushDistance }
                    else if minD == dTop { candidate.y = noFly.minY - pushDistance }
                    else { candidate.y = noFly.maxY + pushDistance }
                }
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

// MARK: - Friends Consistency Leaderboard

struct FriendsLeaderboardPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let dashboard: AccountabilityDashboard

    @State private var isExpanded = false

    private struct LeaderEntry: Identifiable {
        let id: Int64
        let displayName: String
        let consistency: Int
        let isCurrentUser: Bool
    }

    private var entries: [LeaderEntry] {
        var result: [LeaderEntry] = [
            LeaderEntry(
                id: -1,
                displayName: dashboard.profile.displayName,
                consistency: dashboard.level.weeklyConsistencyPercent,
                isCurrentUser: true
            )
        ]
        let friends = (dashboard.social?.updates ?? []).map {
            LeaderEntry(id: $0.userId, displayName: $0.displayName, consistency: $0.weeklyConsistencyPercent, isCurrentUser: false)
        }
        result.append(contentsOf: friends)
        return result.sorted { $0.consistency > $1.consistency }
    }

    private var hasFriends: Bool { !(dashboard.social?.updates ?? []).isEmpty }
    private var currentUserRank: Int {
        (entries.firstIndex { $0.isCurrentUser } ?? 0) + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            pillButton
            if isExpanded {
                leaderboardDropdown
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isExpanded)
    }

    private var pillButton: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CleanShotTheme.gold)
                Text(hasFriends ? "Rank #\(currentUserRank)" : "Friends")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                if hasFriends {
                    Text("\(dashboard.level.weeklyConsistencyPercent)%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CleanShotTheme.success)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [CleanShotTheme.gold.opacity(0.35), CleanShotTheme.gold.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: .black.opacity(0.07), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var leaderboardDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entries.count <= 1 {
                noFriendsPrompt
            } else {
                ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                    leaderRow(rank: index + 1, entry: entry)
                    if index < min(entries.count, 5) - 1 {
                        Divider().opacity(0.3).padding(.horizontal, 10)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CleanShotTheme.stroke(for: colorScheme), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
        .padding(.top, 4)
    }

    private func leaderRow(rank: Int, entry: LeaderEntry) -> some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(rankColor(rank))
                .frame(width: 16)

            if rank <= 3 {
                Image(systemName: rankMedal(rank))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(rankColor(rank))
                    .frame(width: 14)
            } else {
                Color.clear.frame(width: 14)
            }

            Text(entry.isCurrentUser ? "You" : entry.displayName)
                .font(.system(size: 12, weight: entry.isCurrentUser ? .semibold : .medium))
                .foregroundStyle(entry.isCurrentUser ? CleanShotTheme.accent : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 52, height: 4)
                Capsule()
                    .fill(entry.isCurrentUser ? CleanShotTheme.accent : CleanShotTheme.success)
                    .frame(width: 52 * CGFloat(entry.consistency) / 100.0, height: 4)
            }

            Text("\(entry.consistency)%")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            entry.isCurrentUser
                ? CleanShotTheme.accent.opacity(colorScheme == .dark ? 0.08 : 0.05)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var noFriendsPrompt: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Add friends to compare consistency")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return CleanShotTheme.gold
        case 2: return Color.gray.opacity(0.85)
        case 3: return CleanShotTheme.warning.opacity(0.8)
        default: return .secondary
        }
    }

    private func rankMedal(_ rank: Int) -> String {
        switch rank {
        case 1: return "trophy.fill"
        case 2: return "star.fill"
        case 3: return "flame.fill"
        default: return "circle"
        }
    }
}

// MARK: - Ambient done-habit stamps

struct AmbientStamp: View {
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
        .modifier(MatchedStampFrame(
            id: habit.persistentModelID,
            namespace: stampNamespace
        ))
        .onAppear { pulse = true }
    }
}
