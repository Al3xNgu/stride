import DomainKit
import Testing
@testable import FeatureSettings

@Suite("FeatureSettings permission presenters")
struct PermissionPresenterTests {
    @Test("every Watch authorization state has status, detail, and an explicit action policy", arguments: [
        WatchAuthorizationState.notDetermined,
        .restricted,
        .denied,
        .authorized
    ])
    func watchStatesAreMapped(state: WatchAuthorizationState) {
        #expect(!WatchAuthorizationPresenter.statusLabel(for: state).isEmpty)
        #expect(!WatchAuthorizationPresenter.detail(for: state).isEmpty)
        #expect(WatchAuthorizationPresenter.canRequestAuthorization(for: state) == (state == .notDetermined))
    }

    @Test("every Health permission status has explanatory copy and a re-request action", arguments: [
        HealthPermissionStatus.unknown,
        .shouldRequest,
        .unnecessary
    ])
    func healthStatusesAreMapped(status: HealthPermissionStatus) {
        #expect(!HealthPermissionPresenter.statusLabel(for: status).isEmpty)
        #expect(!HealthPermissionPresenter.detail(for: status).isEmpty)
        #expect(HealthPermissionPresenter.canRequestAccess(for: status))
    }

    @Test("typed Health operational errors map to non-empty user-facing messages", arguments: [
        HealthPermissionPrimingError.unavailable,
        .requestFailed("denied by system"),
        .underlying("transport")
    ])
    func healthErrorsAreMapped(error: HealthPermissionPrimingError) {
        #expect(!HealthPermissionPresenter.errorMessage(for: error).isEmpty)
    }
}
