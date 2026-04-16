//
//  Item.swift
//  habit-tracker-macos
//
//  Created by Jashanveer Singh on 4/14/26.
//

import Foundation
import SwiftData

@Model
final class Habit {
    var title: String
    var createdAt: Date
    var completedDayKeys: [String]
    var backendId: Int64?

    init(title: String, createdAt: Date = Date(), completedDayKeys: [String] = [], backendId: Int64? = nil) {
        self.title = title
        self.createdAt = createdAt
        self.completedDayKeys = completedDayKeys
        self.backendId = backendId
    }
}
