#if os(iOS)
import FamilyControls
import SwiftUI

/// Presents Apple's `FamilyActivityPicker` so the user can nominate which
/// apps and categories count as "social media" for verification purposes.
/// The picker UI is opaque — Apple owns it and we can't customize the
/// inside — but we wrap it in a sheet with our own Cancel / Save chrome
/// so the user has a familiar exit path and we know exactly when to
/// persist + restart the monitor.
struct SocialAppsPickerSheet: View {
    @Binding var isPresented: Bool

    /// Mutable copy seeded from the persisted selection at sheet-open
    /// time. Discarded on Cancel; flushed back to `ScreenTimeService` on
    /// Save (which both persists it and (re)starts monitoring).
    @State private var selection: FamilyActivitySelection

    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self._selection = State(initialValue: ScreenTimeService.shared.loadSelection())
    }

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle("Pick social apps")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            ScreenTimeService.shared.storeSelection(selection)
                            isPresented = false
                        }
                        .disabled(selection.applicationTokens.isEmpty
                                  && selection.categoryTokens.isEmpty)
                    }
                }
        }
    }
}
#endif
