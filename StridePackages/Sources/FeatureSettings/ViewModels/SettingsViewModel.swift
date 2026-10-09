import DomainKit
import Foundation
import Observation

/// Screen state and mutations for Settings: the runner's `UserPreferences`
/// (units), Watch-scheduling authorization status with a request flow, and
/// HealthKit read-permission priming via the DomainKit
/// `HealthPermissionPriming` port. The concrete implementation lives in DataKit.
///
/// Default-pace-per-intent editing is intentionally **not** included here:
/// it would need a full pace-range editing UI (minutes/seconds per intent,
/// per `UnitFormatter.paceComponents`) across every `SegmentIntent` case,
/// which is not cheap to add alongside the permission flows this task is
/// scoped around. Left for a follow-up task; `UserPreferences.defaultPacesByIntent`
/// is round-tripped untouched by every save this view model performs.
@MainActor
@Observable
public final class SettingsViewModel {
    /// The currently loaded preferences. Reflects the last successful
    /// `load()` or `save`; never partially updated on a failed save.
    public private(set) var preferences: UserPreferences

    /// Whether a `load()` call is in flight.
    public private(set) var isLoading = false

    /// The error from the most recent `load()` attempt, or `nil`.
    ///
    /// Per CLAUDE.md rule 5 / the 1.3 reviewer note: a corrupt-data load
    /// failure is surfaced here rather than silently falling back to
    /// defaults, so the view can offer an explicit `resetToDefaults()`
    /// recovery action instead of masking data loss.
    public private(set) var loadError: PreferencesStoreError?

    /// The error from the most recent `save`/`resetToDefaults()` attempt, or `nil`.
    public private(set) var saveError: PreferencesStoreError?

    /// Whether this device/OS supports Watch scheduling
    /// (`WatchSyncService.isSupported`).
    public private(set) var isWatchSupported = false

    /// The current Watch-scheduling authorization state.
    public private(set) var watchAuthorizationState: WatchAuthorizationState = .notDetermined

    /// Whether a `requestWatchAuthorization()` call is in flight.
    public private(set) var isRequestingWatchAuthorization = false

    /// The current HealthKit read-permission request status.
    public private(set) var healthPermissionStatus: HealthPermissionStatus = .unknown

    /// Whether a `requestHealthPermission()` call is in flight.
    public private(set) var isRequestingHealthPermission = false

    /// The error from the most recent Health permission request, or `nil`.
    ///
    /// This is kept separately from `loadError` and `saveError` so a failed
    /// system permission request cannot be mistaken for a preferences
    /// persistence failure. A failed request leaves the last known status in
    /// place and lets the view offer the action again.
    public private(set) var healthPermissionError: HealthPermissionPrimingError?

    private let preferencesStore: PreferencesStore
    private let watchSyncService: WatchSyncService
    private let healthPermissionPriming: HealthPermissionPriming

    /// Creates a settings view model.
    /// - Parameters:
    ///   - preferencesStore: Loads/persists `UserPreferences`.
    ///   - watchSyncService: Reports/requests Watch-scheduling authorization.
    ///   - healthPermissionPriming: Reports/requests HealthKit read
    ///     permission via the DomainKit port (see its doc comment).
    ///   - initialPreferences: Shown before the first `load()` completes.
    ///     Defaults to `UserPreferences()`.
    public init(
        preferencesStore: PreferencesStore,
        watchSyncService: WatchSyncService,
        healthPermissionPriming: HealthPermissionPriming,
        initialPreferences: UserPreferences = UserPreferences()
    ) {
        self.preferencesStore = preferencesStore
        self.watchSyncService = watchSyncService
        self.healthPermissionPriming = healthPermissionPriming
        preferences = initialPreferences
    }

    // MARK: - Loading

    /// Loads preferences and both permission surfaces' current status,
    /// replacing prior state. On a preferences load failure, `preferences`
    /// is left unchanged and `loadError` is set; the permission surfaces are
    /// still refreshed regardless.
    public func load() async {
        guard !isLoading else { return }
        loadError = nil
        healthPermissionError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            preferences = try await preferencesStore.load()
        } catch let error as PreferencesStoreError {
            loadError = error
        } catch {
            loadError = .underlying(String(describing: error))
        }

        isWatchSupported = await watchSyncService.isSupported
        watchAuthorizationState = await watchSyncService.authorizationState
        do {
            healthPermissionStatus = try await healthPermissionPriming.status
        } catch let error as HealthPermissionPrimingError {
            healthPermissionError = error
        } catch {
            healthPermissionError = .underlying(String(describing: error))
        }
    }

    // MARK: - Preferences

    /// Changes the preferred distance/pace display unit and persists it.
    public func setDistanceUnit(_ unit: DistanceUnit) async {
        var updated = preferences
        updated.distanceUnit = unit
        await save(updated)
    }

    /// Records completion of the app-owned onboarding flow without changing
    /// the runner's selected unit or default pace preferences.
    public func completeOnboarding() async {
        guard !preferences.hasCompletedOnboarding else { return }
        var updated = preferences
        updated.hasCompletedOnboarding = true
        await save(updated)
    }

    /// Recovery action for a corrupt-data `loadError`: persists
    /// `UserPreferences()` defaults, replaces `preferences` with them on
    /// success, and clears `loadError`. Never happens silently — this is
    /// only ever invoked from an explicit user action in the view.
    public func resetToDefaults() async {
        await save(UserPreferences())
        if saveError == nil {
            loadError = nil
        }
    }

    private func save(_ preferences: UserPreferences) async {
        saveError = nil
        do {
            try await preferencesStore.save(preferences)
            self.preferences = preferences
        } catch let error as PreferencesStoreError {
            saveError = error
        } catch {
            saveError = .underlying(String(describing: error))
        }
    }

    // MARK: - Watch permission

    /// Requests Watch-scheduling authorization and updates
    /// `watchAuthorizationState` with the result.
    ///
    /// A no-op (aside from re-reading `isSupported`) unless the current
    /// state is `.notDetermined`: `.denied`/`.restricted` have no in-API
    /// re-prompt (RESEARCH-LOG §5) — recovery is the Watch app on iPhone,
    /// not a repeated request here — and `.authorized` needs no re-request.
    public func requestWatchAuthorization() async {
        guard !isRequestingWatchAuthorization,
              isWatchSupported,
              watchAuthorizationState == .notDetermined else { return }
        isRequestingWatchAuthorization = true
        defer { isRequestingWatchAuthorization = false }
        watchAuthorizationState = await watchSyncService.requestAuthorization()
    }

    // MARK: - Health permission

    /// Primes/requests HealthKit read authorization and updates
    /// `healthPermissionStatus` with the result.
    public func requestHealthPermission() async {
        guard !isRequestingHealthPermission else { return }
        healthPermissionError = nil
        isRequestingHealthPermission = true
        defer { isRequestingHealthPermission = false }
        do {
            healthPermissionStatus = try await healthPermissionPriming.requestAccess()
        } catch let error as HealthPermissionPrimingError {
            healthPermissionError = error
        } catch {
            healthPermissionError = .underlying(String(describing: error))
        }
    }
}
