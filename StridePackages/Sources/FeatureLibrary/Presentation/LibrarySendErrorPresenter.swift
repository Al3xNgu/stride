import DomainKit

/// Maps `LibrarySendError` into runner-facing copy for the send/schedule/
/// retry failure alert.
///
/// Exhaustive with no `default:` case, matching every other presenter in
/// this module.
enum LibrarySendErrorPresenter {
    static func message(for error: LibrarySendError) -> String {
        switch error {
        case .workoutNotFound:
            return "This workout couldn't be found — it may have just been deleted."

        case let .invalidWorkout(issues):
            return "This workout has \(issues.count) unresolved issue(s) and can't be sent yet. " +
                "Fix them in the builder first."

        case let .repository(repositoryError):
            return "Couldn't complete that action: \(repositoryError)"

        case let .underlying(description):
            return "Something went wrong: \(description)"
        }
    }
}
