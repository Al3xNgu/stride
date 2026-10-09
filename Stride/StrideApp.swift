import Observation
import SwiftUI
import UIKit

/// Launch bridge installs the HealthKit observer before a scene is needed.
@MainActor
@Observable
final class StrideAppDelegate: NSObject, UIApplicationDelegate {
    var container: StrideAppContainer?
    var startupFailed = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        prepareStore()
        return true
    }

    func prepareStore() {
        guard container == nil else { return }
        do {
            let created = try StrideAppContainer(
                uiTesting: ProcessInfo.processInfo.arguments.contains("-StrideUITestMode")
            )
            container = created
            startupFailed = false
            created.observeAtLaunch()
        } catch {
            // Preserve the store for recovery; never erase it or fall back to memory.
            startupFailed = true
        }
    }
}

@main
struct StrideApp: App {
    @UIApplicationDelegateAdaptor(StrideAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            if let container = delegate.container {
                ContentView(container: container)
            } else {
                ContentUnavailableView {
                    Label("Couldn’t open your data", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your saved data has been kept. Try opening it again.")
                } actions: {
                    Button("Try Again") { delegate.prepareStore() }
                }
            }
        }
    }
}
