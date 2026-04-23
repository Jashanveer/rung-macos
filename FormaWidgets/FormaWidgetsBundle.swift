import SwiftUI
import WidgetKit

@main
struct FormaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayRingWidget()
        StreakWidget()
        XPLevelWidget()
        ChecklistWidget()
        WeeklyWidget()
        FriendsProgressWidget()
        MenteeViewWidget()
        DashboardWidget()
        LeaderboardWidget()
        CommandCenterWidget()
    }
}
