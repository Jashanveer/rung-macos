import SwiftUI

/// Per-habit reminder editor. Replaces the older single-bucket
/// `reminderWindow` picker with a list of explicit reminder rules:
/// time-of-day, location, after-calendar-event, energy-peak.
///
/// Reminders persist on the backend via `HabitBackendStore`. The
/// legacy `Habit.reminderWindow` column stays in place for clients
/// on older builds.
struct HabitRemindersSheet: View {
    let habit: Habit
    @ObservedObject var backend: HabitBackendStore

    @Environment(\.dismiss) private var dismiss
    @State private var reminders: [HabitReminder] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var addingKind: HabitReminder.Kind?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    listContent
                }
            }
            .navigationTitle("Reminders")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $addingKind) { kind in
                ReminderEditor(kind: kind) { newReminder in
                    addingKind = nil
                    Task { await create(newReminder) }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            if let loadError {
                Section {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                if reminders.isEmpty {
                    Text("No reminders yet. Pick a trigger below.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 4)
                } else {
                    ForEach(reminders) { reminder in
                        ReminderRow(reminder: reminder, onToggle: { newValue in
                            Task { await setEnabled(reminder, enabled: newValue) }
                        })
                    }
                    .onDelete { offsets in
                        Task { await delete(at: offsets) }
                    }
                }
            } header: {
                Text("Active reminders")
            } footer: {
                if !reminders.isEmpty {
                    Text("Reminders fire on the device. The cloud just remembers them so they sync when you sign in elsewhere.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Add") {
                ForEach(HabitReminder.Kind.allCases) { kind in
                    Button {
                        addingKind = kind
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.systemImage)
                                .frame(width: 24)
                                .foregroundStyle(.tint)
                            Text(kind.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .disabled(working)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Actions

    private func load() async {
        guard let backendId = habit.backendId else {
            // Habit hasn't synced yet; nothing to fetch. UI shows the
            // empty-state hint and the user can still configure
            // reminders once their first sync round-trips.
            isLoading = false
            return
        }
        isLoading = true
        loadError = nil
        do {
            reminders = try await backend.listHabitReminders(habitID: backendId)
        } catch {
            loadError = "Couldn't load reminders — \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func create(_ reminder: HabitReminder) async {
        guard let backendId = habit.backendId else { return }
        working = true
        do {
            let created = try await backend.createHabitReminder(habitID: backendId, reminder: reminder)
            reminders.append(created)
        } catch {
            loadError = "Couldn't save reminder — \(error.localizedDescription)"
        }
        working = false
    }

    private func setEnabled(_ reminder: HabitReminder, enabled: Bool) async {
        guard let backendId = habit.backendId, let reminderId = reminder.id else { return }
        var copy = reminder
        copy.enabled = enabled
        working = true
        do {
            let updated = try await backend.updateHabitReminder(habitID: backendId, reminderID: reminderId, reminder: copy)
            if let idx = reminders.firstIndex(where: { $0.id == reminderId }) {
                reminders[idx] = updated
            }
        } catch {
            loadError = "Couldn't toggle reminder — \(error.localizedDescription)"
        }
        working = false
    }

    private func delete(at offsets: IndexSet) async {
        guard let backendId = habit.backendId else { return }
        let toDelete = offsets.compactMap { reminders[$0].id }
        // Optimistic remove so the row disappears immediately; restore
        // on failure.
        let snapshot = reminders
        reminders.remove(atOffsets: offsets)
        for reminderID in toDelete {
            do {
                try await backend.deleteHabitReminder(habitID: backendId, reminderID: reminderID)
            } catch {
                reminders = snapshot
                loadError = "Couldn't delete reminder — \(error.localizedDescription)"
                return
            }
        }
    }
}

private struct ReminderRow: View {
    let reminder: HabitReminder
    let onToggle: (Bool) -> Void

    @State private var isEnabled: Bool

    init(reminder: HabitReminder, onToggle: @escaping (Bool) -> Void) {
        self.reminder = reminder
        self.onToggle = onToggle
        _isEnabled = State(initialValue: reminder.enabled)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.kind.systemImage)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.kind.label)
                    .font(.body)
                Text(reminder.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: $isEnabled)
                .labelsHidden()
                .onChange(of: isEnabled) { _, newValue in
                    onToggle(newValue)
                }
        }
        .padding(.vertical, 2)
    }
}

/// Minimal editor — currently only `timeOfDay` has full UI; other
/// kinds save with sensible defaults so the model and network round-
/// trip can be exercised end-to-end. Richer pickers (location picker,
/// calendar event chooser) ship in follow-ups.
private struct ReminderEditor: View {
    let kind: HabitReminder.Kind
    let onSave: (HabitReminder) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var times: [Date] = [defaultTime()]
    @State private var weekdays: [Bool] = Array(repeating: true, count: 7)
    @State private var snoozeMinutes: Int = 0
    @State private var locationLabel: String = ""
    @State private var calendarKeyword: String = "meeting"
    @State private var energyMode: EnergyMode = .high

    enum EnergyMode: String, CaseIterable, Identifiable {
        case high, low
        var id: String { rawValue }
        var label: String { self == .high ? "Energy peak" : "Energy trough" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(kind.label) {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 26))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(.tint)
                        .padding(.vertical, 4)
                }

                kindSpecificEditor

                if kind == .timeOfDay {
                    Section("Days") {
                        weekdayPicker
                    }
                }

                Section("Snooze") {
                    Picker("Snooze for", selection: $snoozeMinutes) {
                        Text("Off").tag(0)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("30 min").tag(30)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(kind.label)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(buildReminder())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var kindSpecificEditor: some View {
        switch kind {
        case .timeOfDay:
            Section("Times") {
                ForEach(times.indices, id: \.self) { idx in
                    DatePicker("Time \(idx + 1)", selection: $times[idx], displayedComponents: .hourAndMinute)
                }
                .onDelete { offsets in
                    times.remove(atOffsets: offsets)
                    if times.isEmpty { times = [Self.defaultTime()] }
                }
                Button {
                    times.append(Self.defaultTime())
                } label: {
                    Label("Add another time", systemImage: "plus.circle.fill")
                }
            }
        case .location:
            Section("Place") {
                TextField("Saved place name (e.g. Home, Gym)", text: $locationLabel)
                    .textFieldStyle(.automatic)
                Text("Pick a saved place. Geofencing fires the reminder when you arrive.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .afterCalendarEvent:
            Section("Calendar trigger") {
                TextField("Event keyword (e.g. meeting, standup)", text: $calendarKeyword)
                Text("The reminder fires whenever an event matching this keyword ends.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .energyPeak:
            Section("Energy mode") {
                Picker("When", selection: $energyMode) {
                    ForEach(EnergyMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("Uses your sleep insights + chronotype to pick the right moment in the day.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weekdayPicker: some View {
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                Button {
                    weekdays[i].toggle()
                } label: {
                    Text(labels[i])
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(weekdays[i] ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(weekdays[i] ? Color.accentColor : .clear, lineWidth: 1)
                        )
                        .foregroundStyle(weekdays[i] ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private func buildReminder() -> HabitReminder {
        let payload: String?
        switch kind {
        case .timeOfDay:
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            payload = times
                .map { formatter.string(from: $0) }
                .sorted()
                .joined(separator: ",")
        case .location:
            payload = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : locationLabel
        case .afterCalendarEvent:
            payload = calendarKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : calendarKeyword
        case .energyPeak:
            payload = energyMode.rawValue
        }
        let mask: Int? = kind == .timeOfDay ? Self.weekdayMask(weekdays) : nil
        return HabitReminder(
            id: nil,
            kind: kind,
            payload: payload,
            weekdayMask: mask,
            snoozeMinutes: snoozeMinutes > 0 ? snoozeMinutes : nil,
            enabled: true
        )
    }

    private static func defaultTime() -> Date {
        let now = Date()
        let cal = Calendar.current
        return cal.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
    }

    private static func weekdayMask(_ flags: [Bool]) -> Int? {
        let mask = flags.enumerated().reduce(into: 0) { acc, pair in
            if pair.element { acc |= (1 << pair.offset) }
        }
        if mask == HabitReminder.allWeekdays { return nil }
        if mask == 0 { return nil }
        return mask
    }
}
