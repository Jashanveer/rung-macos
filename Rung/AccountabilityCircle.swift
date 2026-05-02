import Foundation

/// Public/private accountability circle. Replaces the old "everyone is
/// in one big leaderboard" model with focused groups: a dorm hallway,
/// a running club, three friends keeping each other honest. Circles
/// own their own weekly perfect-day leaderboard; verified-only circles
/// disqualify self-report checks so the social score actually means
/// something.
///
/// Wire-format mirrors the V18 backend tables (`accountability_circles`
/// + `circle_members`).
struct AccountabilityCircle: Codable, Identifiable, Hashable {
    let id: Int64
    let ownerId: Int64
    let name: String
    let description: String?
    let visibility: Visibility
    /// Required for PRIVATE circles (the share code), nil for PUBLIC.
    let joinCode: String?
    /// When true, only `auto`/`partial` tier checks count toward the
    /// circle's leaderboard. Self-report checks still record but
    /// don't earn rank — the circle's whole point is that scores are
    /// trustworthy.
    let verifiedOnly: Bool
    let memberCount: Int
    let createdAt: Date

    enum Visibility: String, Codable, CaseIterable, Identifiable {
        case `public` = "PUBLIC"
        case `private` = "PRIVATE"
        var id: String { rawValue }
        var label: String { self == .public ? "Public" : "Private" }
        var systemImage: String {
            self == .public ? "globe" : "lock.fill"
        }
    }
}

/// One member inside a circle. The score field is computed by the
/// backend per ISO week and reflects the circle's `verifiedOnly` rule.
struct CircleMember: Codable, Identifiable, Hashable {
    let id: Int64
    let userId: Int64
    let displayName: String
    let username: String?
    let avatarURL: String?
    let role: Role
    /// Perfect days this ISO week (the leaderboard's primary signal).
    let weeklyPerfectDays: Int
    /// Tier-weighted score for the week (auto×10, partial×5,
    /// selfReport×1). 0 in `verifiedOnly` circles when the member
    /// has only self-reported checks.
    let weeklyVerifiedScore: Int
    let isCurrentUser: Bool

    enum Role: String, Codable {
        case owner = "OWNER"
        case admin = "ADMIN"
        case member = "MEMBER"
    }
}

/// Full circle dashboard the iOS UI renders for the detail screen.
/// Returned by `GET /api/circles/{id}`.
struct CircleDashboard: Codable, Hashable {
    let circle: AccountabilityCircle
    let members: [CircleMember]
    /// Recent posts scoped to this circle (visibility=CIRCLE).
    let posts: [CirclePost]
}

/// Lightweight feed item scoped to a circle. Different shape from
/// the global `SocialPost` because we want author + timestamp + body
/// only — no comments, no reactions yet.
struct CirclePost: Codable, Identifiable, Hashable {
    let id: Int64
    let authorDisplayName: String
    let body: String
    let createdAt: Date
}
