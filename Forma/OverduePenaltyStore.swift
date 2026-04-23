import Foundation

/// Local accumulator for XP docked when a task slips past its due date and no
/// streak freeze was available to absorb the miss. Backend XP is read-only from
/// the client, so the penalty is held in UserDefaults per signed-in user and
/// subtracted at display time. It carries across sessions on the same device.
enum OverduePenaltyStore {
    /// XP docked per overdue task when no freeze can be consumed.
    static let xpPerOverdueTask = 50

    private static func key(for userId: String?) -> String {
        "overdueXpPenalty_\(userId ?? "anon")"
    }

    static func accumulated(for userId: String?) -> Int {
        UserDefaults.standard.integer(forKey: key(for: userId))
    }

    static func add(_ amount: Int, for userId: String?) {
        let total = accumulated(for: userId) + max(0, amount)
        UserDefaults.standard.set(total, forKey: key(for: userId))
    }

    static func reset(for userId: String?) {
        UserDefaults.standard.removeObject(forKey: key(for: userId))
    }

    /// Net XP after subtracting accumulated penalty, never below zero.
    static func adjustedXP(_ baseXP: Int, for userId: String?) -> Int {
        max(0, baseXP - accumulated(for: userId))
    }
}
