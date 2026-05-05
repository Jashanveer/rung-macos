import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

/// Dedicated full-screen "add a task" surface. Big central voice button
/// is the primary affordance — tap to dictate. The same control morphs
/// to a Done state once the user has spoken or scribbled a title, and a
/// secondary "Type" button drops straight to the watchOS keyboard for
/// users who prefer scribble / hardware keyboard. This replaces the
/// tiny floating mic in HabitsTab — the user said it was hard to hit
/// and asked for a dedicated screen with a large voice target.
///
/// All entries created here ride through `WatchSession.createHabit`,
/// which today posts via WC and triggers a backend refresh; on iOS the
/// new row gets `entryType == .task` if the title looks task-shaped,
/// otherwise it stays a habit (iPhone owns that classification).
struct AddEntryView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.watchFontScale) private var scale: Double

    @State private var dictatedTitle: String = ""
    @State private var typeSheetShown: Bool = false
    @State private var didCommit: Bool = false
    /// Surfaces the duplicate-title guard inline so the user sees
    /// *why* the Add tap didn't create a row. Auto-clears the moment
    /// they edit / re-dictate.
    @State private var duplicateError: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WatchPageTitle("Add", accent: WatchTheme.cAmber)
                    .padding(.horizontal, 12)

                Text(headlineText)
                    .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                    .foregroundStyle(WatchTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                voiceButton

                if !dictatedTitle.isEmpty && !didCommit {
                    confirmCard
                }

                if let duplicateError {
                    Text(duplicateError)
                        .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(WatchTheme.cRose)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .transition(.opacity)
                }

                if !didCommit {
                    typeButton
                }

                Text("Speak the task or hit Type to use the keyboard.")
                    .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(WatchTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
            }
            .padding(.bottom, 12)
        }
        .watchWashBackground(.amber)
        .sheet(isPresented: $typeSheetShown) {
            TextInputSheet(text: $dictatedTitle, onSubmit: commit)
        }
    }

    // MARK: - Big voice button

    /// The primary affordance — a large pill-shaped glass disc with a
    /// gradient mic glyph. Tapping presents the system dictation /
    /// Scribble chooser via the watchOS `TextField` input route, which
    /// already handles voice + keyboard + Scribble in one sheet. We
    /// route through `TextInputSheet` so the same control covers all
    /// three input methods without forking the binding logic.
    private var voiceButton: some View {
        Button {
            duplicateError = nil
            typeSheetShown = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [WatchTheme.cAmber, WatchTheme.cPeach.opacity(0.85)],
                            center: .topLeading,
                            startRadius: 1,
                            endRadius: 80
                        )
                    )
                Circle()
                    .stroke(Color.white.opacity(0.32), lineWidth: 0.8)
                Image(systemName: "mic.fill")
                    .font(.system(size: 38 * scale, weight: .heavy))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, options: .speed(1.5), value: typeSheetShown)
            }
            .frame(width: 96 * scale, height: 96 * scale)
            .shadow(color: WatchTheme.cAmber.opacity(0.6), radius: 14, y: 4)
        }
        .buttonStyle(WatchPressStyle())
        .padding(.top, 6)
    }

    // MARK: - Confirm + secondary buttons

    /// After dictation lands, surface the captured title plus an
    /// explicit "Add" action so the user can review and commit. The
    /// review step matters because watchOS dictation is fast but
    /// sometimes wrong — committing silently would create the wrong
    /// task and force the user to delete it on iPhone.
    private var confirmCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HEARD")
                .font(WatchTheme.font(.label, scale: scale, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(WatchTheme.inkSoft)
            Text(dictatedTitle)
                .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                .foregroundStyle(WatchTheme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                Button {
                    commit(dictatedTitle)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Add")
                            .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .liquidGlassSurface(cornerRadius: 11, tint: WatchTheme.cMint, strong: true)
                }
                .buttonStyle(WatchPressStyle())

                Button {
                    dictatedTitle = ""
                    duplicateError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .liquidGlassSurface(cornerRadius: 999, tint: WatchTheme.cRose)
                }
                .buttonStyle(WatchPressStyle())
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassSurface(cornerRadius: 14, strong: true)
        .padding(.horizontal, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(WatchMotion.snappy, value: dictatedTitle)
    }

    private var typeButton: some View {
        Button {
            duplicateError = nil
            typeSheetShown = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .foregroundStyle(WatchTheme.cCyan)
                Text("Type")
                    .font(WatchTheme.font(.body, scale: scale, weight: .medium))
                    .foregroundStyle(WatchTheme.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .liquidGlassSurface(cornerRadius: 11)
        }
        .buttonStyle(WatchPressStyle())
        .padding(.horizontal, 10)
        .padding(.top, 2)
    }

    // MARK: - Copy

    private var headlineText: String {
        if didCommit { return "Added · swipe to Today" }
        if dictatedTitle.isEmpty { return "Tap to dictate a task" }
        return "Review and add"
    }

    // MARK: - Commit path

    private func commit(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Duplicate guard — match against everything we know about
        // (pending + completed). Case-insensitive, whitespace-trimmed,
        // mirrors the iOS-side `Habit.duplicateMatchKey` so a title
        // typed on watch reads as duplicate the same way it would on
        // iPhone.
        if isDuplicate(title: trimmed) {
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.failure)
            #endif
            withAnimation(WatchMotion.snappy) {
                duplicateError = "Already in your list — pick a different title."
            }
            return
        }

        session.createHabit(title: trimmed)
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.success)
        #endif
        // Switch into the celebration state. We DON'T dismiss — the
        // Add screen is a tab, not a sheet, so dismiss() is a no-op.
        // Instead clear the dictated text + the review card and let
        // the user swipe back to Today (or stay here to dictate
        // another). After ~1.5s reset to the idle "Tap to dictate"
        // state so a future visit doesn't open mid-celebration.
        withAnimation(WatchMotion.snappy) {
            dictatedTitle = ""
            duplicateError = nil
            didCommit = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(WatchMotion.smooth) {
                didCommit = false
            }
        }
    }

    /// True when the snapshot already contains a habit/task whose
    /// trimmed-lowercased title matches `title`. Cheap O(n) scan; n
    /// is at most a few dozen rows.
    private func isDuplicate(title: String) -> Bool {
        let key = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !key.isEmpty else { return false }
        let all = session.snapshot.pendingHabits + session.snapshot.completedHabits
        return all.contains { row in
            row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == key
        }
    }
}

// MARK: - Text input sheet

/// The watchOS dictation / Scribble / keyboard sheet wrapper. A bare
/// TextField is enough — watchOS auto-presents the input chooser when
/// the field becomes first responder, which means the user gets the
/// same dictation chooser the system Reminders app uses. Submitting
/// (or dismissing with content) commits via the supplied callback.
private struct TextInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.watchFontScale) private var scale: Double
    @Binding var text: String
    var onSubmit: (String) -> Void

    @State private var didSubmit: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Text("New task")
                .font(WatchTheme.font(.caption, scale: scale, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(WatchTheme.inkSoft)
            TextField("Speak or scribble", text: $text)
                .font(WatchTheme.font(.body, scale: scale, weight: .semibold))
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .onSubmit {
                    submit()
                }
            Button("Done") {
                submit()
            }
            .font(WatchTheme.font(.body, scale: scale, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WatchTheme.brandGradient)
            )
            .buttonStyle(WatchPressStyle())
        }
        .padding(12)
        .watchWashNavigationBackground(.amber)
        .onDisappear {
            // Same Scribble / Dictation "Done" footgun the old voice
            // sheet had — the system button dismisses the sheet
            // without firing onSubmit on the underlying TextField. If
            // we still hold non-empty content and the user didn't go
            // through the explicit Done button, treat the dismiss as
            // an implicit submit so dictated text isn't lost.
            guard !didSubmit else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onSubmit(trimmed)
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismiss()
            return
        }
        didSubmit = true
        onSubmit(trimmed)
        dismiss()
    }
}

#if DEBUG
#Preview {
    AddEntryView()
        .environmentObject(WatchSession.preview(hasRealData: true, snapshot: .previewSample()))
}
#endif
