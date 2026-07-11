//
//  WorkoutKitSpikeView.swift
//  Stride
//
//  Task 0.6 — DEBUG-only instrumentation panel for a human to exercise WorkoutKit on a physical
//  iPhone with a paired Apple Watch. See WorkoutKitSpikeModel.swift for the composed workout and
//  every HARDWARE-VERIFY note. Findings go back into docs/RESEARCH-LOG.md.
//

#if DEBUG

import SwiftUI
import WorkoutKit

struct WorkoutKitSpikeView: View {
    @State private var model = WorkoutKitSpikeModel()

    var body: some View {
        @Bindable var model = model

        List {
            Section("1. Environment") {
                Button("Refresh environment readout") {
                    Task { await model.readEnvironment() }
                }
            }

            Section("2. Authorization") {
                Button("Request authorization") {
                    Task { await model.requestAuthorization() }
                }
            }

            Section("3. Pre-flight checks") {
                Button("Run supports* checks") {
                    model.runPreflightChecks()
                }
            }

            Section("4. Serialize") {
                Button("Serialize plan") {
                    model.serializePlan()
                }
            }

            Section("5 & 6. Schedule") {
                Button("Schedule tomorrow 07:00") {
                    Task { await model.scheduleTomorrowMorning() }
                }
                Button("Schedule again tomorrow 18:00 (same plan.id)") {
                    Task { await model.scheduleTomorrowEvening() }
                }
            }

            Section("7. Remove") {
                Button("Remove 07:00 schedule") {
                    Task { await model.removeMorningSchedule() }
                }
                Button("Remove 18:00 schedule") {
                    Task { await model.removeEveningSchedule() }
                }
                Button("Remove ALL scheduled workouts", role: .destructive) {
                    Task { await model.removeAll() }
                }
            }

            Section("8. Preview") {
                Button("Toggle workout preview") {
                    model.isPreviewPresented.toggle()
                }
            }

            Section("Log") {
                ForEach(model.logEntries) { entry in
                    Text("\(entry.formattedTimestamp) — \(entry.message)")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .navigationTitle("WorkoutKit Spike")
        .task {
            await model.readEnvironment()
        }
        .workoutPreview(model.plan, isPresented: $model.isPreviewPresented)
    }
}

#Preview {
    NavigationStack {
        WorkoutKitSpikeView()
    }
}

#endif
