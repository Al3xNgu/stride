import SwiftUI

struct ContentView: View {
    let container: StrideAppContainer
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "figure.run")
                    .font(.largeTitle)
                Text("Your running history")
                    .font(.title2)
                Text("Connect Health to import running workouts, distance, and heart rate for your history and records.")
                    .multilineTextAlignment(.center)
                Button(container.hasRequestedAccess ? "Refresh History" : "Connect Health") {
                    Task { await container.refresh(requestAccess: true) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(container.isRefreshing)
                if container.isRefreshing { ProgressView("Updating history…") }
                if let count = container.importedRunCount {
                    Text("\(count) runs in your history")
                    if count == 0 {
                        Text("No runs are available. You can check Stride’s read access in the Health app.")
                            .font(.footnote)
                    }
                }
                if container.ingestionError != nil {
                    Text("History couldn’t be updated. Your saved runs are still available. Try again.")
                        .foregroundStyle(.red)
                }
                if container.deliveryError != nil {
                    Text("Background updates are unavailable. Open Stride to refresh your history.")
                        .font(.footnote)
                }
                #if DEBUG
                NavigationLink("WorkoutKit Spike (Debug)") { WorkoutKitSpikeView() }
                #endif
            }
            .padding()
            .navigationTitle("Stride")
            .task { await container.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await container.refresh() }
                }
            }
        }
    }
}
