import DesignSystem
import SwiftUI

/// The "Send to Watch" confirmation sheet: send for the next available slot,
/// or pick a specific date/time (the §7 "schedule-by-date" flow).
struct ScheduleSheetView: View {
    let workoutName: String
    let now: Date
    let onSendNow: () -> Void
    let onSchedule: (Date) -> Void
    let onCancel: () -> Void

    @State private var sendNow = true
    @State private var selectedDate: Date

    init(
        workoutName: String,
        now: Date,
        onSendNow: @escaping () -> Void,
        onSchedule: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.workoutName = workoutName
        self.now = now
        self.onSendNow = onSendNow
        self.onSchedule = onSchedule
        self.onCancel = onCancel
        _selectedDate = State(initialValue: now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Send now", isOn: $sendNow)
                    if !sendNow {
                        DatePicker(
                            "Date",
                            selection: $selectedDate,
                            in: now...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                } footer: {
                    Text("Sends \"\(workoutName)\" to your paired Apple Watch's Workout app.")
                }
            }
            .navigationTitle("Send to Watch")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        if sendNow {
                            onSendNow()
                        } else {
                            onSchedule(selectedDate)
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    ScheduleSheetView(
        workoutName: "5x1km Intervals",
        now: PreviewFixtures.referenceDate,
        onSendNow: {},
        onSchedule: { _ in },
        onCancel: {}
    )
}
#endif
