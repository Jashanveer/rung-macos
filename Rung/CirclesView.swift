import SwiftUI

/// Top-level view for accountability circles. Lists the user's
/// circles, lets them create a new one or join via code, and routes
/// into a per-circle dashboard. Powered by the V18 backend endpoints
/// at `/api/circles`.
struct CirclesView: View {
    @ObservedObject var backend: HabitBackendStore

    @Environment(\.dismiss) private var dismiss
    @State private var myCircles: [AccountabilityCircle] = []
    @State private var publicCircles: [AccountabilityCircle] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingCreate = false
    @State private var showingJoin = false
    @State private var selectedCircle: AccountabilityCircle?

    var body: some View {
        NavigationStack {
            Group {
                if myCircles.isEmpty {
                    emptyState
                } else {
                    populatedList
                }
            }
            .navigationTitle("Circles")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingCreate = true
                        } label: {
                            Label("Create circle", systemImage: "plus.circle.fill")
                        }
                        Button {
                            showingJoin = true
                        } label: {
                            Label("Join with code", systemImage: "key.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateCircleSheet(backend: backend) { created in
                    showingCreate = false
                    myCircles.insert(created, at: 0)
                }
            }
            .sheet(isPresented: $showingJoin) {
                JoinCircleSheet(backend: backend) { joined in
                    showingJoin = false
                    if !myCircles.contains(where: { $0.id == joined.id }) {
                        myCircles.insert(joined, at: 0)
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { selectedCircle != nil },
                set: { if !$0 { selectedCircle = nil } }
            )) {
                if let circle = selectedCircle {
                    CircleDashboardView(circle: circle, backend: backend)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 620, idealHeight: 720)
        #endif
        .dismissOnSessionExpired()
        .task { await load() }
    }

    @ViewBuilder
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.red.opacity(0.10))
                        )
                }

                EmptyCirclesExplainer(
                    onCreate: { showingCreate = true },
                    onJoin:   { showingJoin = true }
                )

                if !publicCircles.isEmpty {
                    DiscoverSection(circles: Array(publicCircles.prefix(5))) { circle in
                        selectedCircle = circle
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var populatedList: some View {
        List {
            if let loadError {
                Section {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                ForEach(myCircles) { circle in
                    Button {
                        selectedCircle = circle
                    } label: {
                        CircleSummaryRow(circle: circle)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Your circles")
            } footer: {
                Text("Small private groups where the leaderboard means something — verified-only circles disqualify self-report checks.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !publicCircles.isEmpty {
                Section("Discover") {
                    ForEach(publicCircles.prefix(5)) { circle in
                        Button {
                            selectedCircle = circle
                        } label: {
                            CircleSummaryRow(circle: circle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            async let mine = backend.circleRepository.listMine()
            async let publicList = backend.circleRepository.listPublic()
            myCircles = try await mine
            publicCircles = try await publicList
        } catch {
            loadError = "Couldn't load circles — \(error.localizedDescription)"
        }
        isLoading = false
    }
}

/// First-run explainer rendered inside the Circles list when the user
/// has joined zero circles. Replaces the bland one-line "you're not in
/// any circles" placeholder with a real explanation of what a circle
/// is, why it's different from the rest of the dashboard, and the two
/// CTAs (Create / Join) that move them forward.
private struct EmptyCirclesExplainer: View {
    let onCreate: () -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Circles — your accountability crew")
                        .font(.system(size: 20, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A small private group, capped at ~25 people, with its own leaderboard and feed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                explainerRow(
                    systemImage: "checkmark.seal.fill",
                    tint: .green,
                    title: "Verified-only ranking",
                    body: "Self-report checks still post to the feed but don't earn rank — keeps the leaderboard honest among friends."
                )
                explainerRow(
                    systemImage: "lock.fill",
                    tint: .indigo,
                    title: "Private by default",
                    body: "You get a join code to share. Hidden from public discovery; nobody outside the circle sees the activity."
                )
                explainerRow(
                    systemImage: "flame.fill",
                    tint: .orange,
                    title: "Stakes that mean something",
                    body: "Smaller than a public feed, more peer-reviewed than a 1:1 mentor. The size that actually changes behaviour."
                )
            }

            VStack(spacing: 10) {
                Button(action: onCreate) {
                    Label("Create a circle", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onJoin) {
                    Label("Join with a code", systemImage: "key.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Text("Got a code? Tap **Join with a code** and paste it. The owner can copy it from the circle's menu.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func explainerRow(systemImage: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DiscoverSection: View {
    let circles: [AccountabilityCircle]
    let onSelect: (AccountabilityCircle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DISCOVER")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.4)
                .padding(.horizontal, 4)

            VStack(spacing: 6) {
                ForEach(circles) { circle in
                    Button {
                        onSelect(circle)
                    } label: {
                        CircleSummaryRow(circle: circle)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CircleSummaryRow: View {
    let circle: AccountabilityCircle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: circle.visibility.systemImage)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(circle.name)
                        .font(.body.weight(.semibold))
                    if circle.verifiedOnly {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .accessibilityLabel("Verified-only")
                    }
                }
                Text("\(circle.memberCount) member\(circle.memberCount == 1 ? "" : "s") · \(circle.visibility.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct CircleDashboardView: View {
    let circle: AccountabilityCircle
    @ObservedObject var backend: HabitBackendStore

    @Environment(\.dismiss) private var dismiss
    @State private var dashboard: CircleDashboard?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingShareSheet = false
    @State private var leavingConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let dashboard {
                    list(dashboard)
                } else if let loadError {
                    VStack {
                        Spacer()
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }
            }
            .navigationTitle(circle.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if let code = circle.joinCode {
                            Button {
                                #if os(iOS)
                                UIPasteboard.general.string = code
                                #endif
                            } label: {
                                Label("Copy join code: \(code)", systemImage: "doc.on.doc")
                            }
                        }
                        Button(role: .destructive) {
                            leavingConfirm = true
                        } label: {
                            Label("Leave circle", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Leave \(circle.name)?", isPresented: $leavingConfirm) {
                Button("Leave", role: .destructive) {
                    Task { await leave() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You won't see new posts from this circle and won't appear in its leaderboard.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 600, idealHeight: 700)
        #endif
        .dismissOnSessionExpired()
        .task { await load() }
    }

    @ViewBuilder
    private func list(_ dashboard: CircleDashboard) -> some View {
        List {
            Section("Leaderboard this week") {
                ForEach(dashboard.members.sorted { $0.weeklyPerfectDays > $1.weeklyPerfectDays }) { member in
                    HStack(spacing: 10) {
                        Text(member.displayName.prefix(1).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.accentColor))
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(member.displayName)
                                    .font(.subheadline.weight(member.isCurrentUser ? .bold : .regular))
                                if member.role == .owner {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                }
                            }
                            Text("\(member.weeklyPerfectDays) perfect day\(member.weeklyPerfectDays == 1 ? "" : "s") · \(member.weeklyVerifiedScore) verified pts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            if !dashboard.posts.isEmpty {
                Section("Recent posts") {
                    ForEach(dashboard.posts) { post in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(post.authorDisplayName)
                                .font(.caption.weight(.semibold))
                            Text(post.body)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func load() async {
        isLoading = true
        do {
            dashboard = try await backend.circleRepository.dashboard(circleID: circle.id)
        } catch {
            loadError = "Couldn't load \(circle.name) — \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func leave() async {
        do {
            try await backend.circleRepository.leave(circleID: circle.id)
            dismiss()
        } catch {
            loadError = "Couldn't leave — \(error.localizedDescription)"
        }
    }
}

private struct CreateCircleSheet: View {
    @ObservedObject var backend: HabitBackendStore
    let onCreated: (AccountabilityCircle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var visibility: AccountabilityCircle.Visibility = .private
    @State private var verifiedOnly: Bool = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Circle name", text: $name)
                    TextField("Optional description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        ForEach(AccountabilityCircle.Visibility.allCases) { kind in
                            HStack {
                                Image(systemName: kind.systemImage)
                                Text(kind.label)
                            }
                            .tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(visibility == .private
                         ? "You'll get a join code to share with up to 25 friends. Hidden from public discovery."
                         : "Anyone can find and join this circle. Good for community challenges.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Scoring") {
                    Toggle("Verified-only", isOn: $verifiedOnly)
                    Text("Self-reported checks still record but don't earn rank in this circle. Keeps the leaderboard honest.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New circle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 560)
        #endif
        .dismissOnSessionExpired()
    }

    private func create() async {
        saving = true
        error = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let created = try await backend.circleRepository.create(
                name: trimmed,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                visibility: visibility,
                verifiedOnly: verifiedOnly
            )
            onCreated(created)
        } catch {
            self.error = "Couldn't create — \(error.localizedDescription)"
        }
        saving = false
    }
}

private struct JoinCircleSheet: View {
    @ObservedObject var backend: HabitBackendStore
    let onJoined: (AccountabilityCircle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code: String = ""
    @State private var joining = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Join code") {
                    TextField("Paste the code", text: $code)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit { Task { await join() } }
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Join circle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { Task { await join() } }
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || joining)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 320, idealHeight: 380)
        #endif
        .dismissOnSessionExpired()
    }

    private func join() async {
        joining = true
        error = nil
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // V18 backend currently routes joins by `{circleId}/join` with
        // the code in the body — the share flow we expect is a deep
        // link that carries both, but a code-only path needs a future
        // `POST /api/circles/redeem` endpoint. Until that lands, this
        // sheet surfaces the limitation honestly instead of failing
        // mysteriously.
        self.error = "Code-only joining lands when the backend adds a redeem endpoint. For now, ask the circle owner for an invite link — tapping it joins automatically."
        _ = trimmed
        joining = false
    }
}

/// Compact card-style entry point shown inside `SettingsPanel` to open
/// the full circles list. Behaves like an inline button with a
/// disclosure chevron — taps push `CirclesView` as a sheet.
struct CirclesEntryCard: View {
    @ObservedObject var backend: HabitBackendStore
    @State private var showingCircles = false

    var body: some View {
        Button {
            showingCircles = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CleanShotTheme.accent)
                    .frame(width: 28, height: 28)
                    .cleanShotSurface(shape: Circle(), level: .control)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Circles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Small private groups · verified-only challenges")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .cleanShotSurface(
                shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                level: .control
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingCircles) {
            CirclesView(backend: backend)
        }
    }
}
