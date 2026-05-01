import SwiftUI
import WidgetKit

@main
struct RungWidgetsBundle: WidgetBundle {
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
        #if os(iOS)
        FocusLiveActivityWidget()
        #endif
    }
}
