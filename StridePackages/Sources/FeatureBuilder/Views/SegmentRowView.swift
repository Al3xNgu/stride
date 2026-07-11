import DesignSystem
import DomainKit
import SwiftUI

/// A single row summarizing a `WorkoutSegment` in the builder's list, or a
/// single `SegmentStep` inside an interval block editor.
struct SegmentRowView: View {
    let segment: WorkoutSegment
    let displayUnit: DisplayDistanceUnit

    var body: some View {
        switch segment {
        case let .step(step):
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(step.intent.displayName)
                    .font(Typography.headline)
                Text(summary(for: step))
                    .font(Typography.caption)
                    .foregroundStyle(Colors.secondaryText)
            }

        case let .intervalBlock(_, steps, repetitions):
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text("Interval Block")
                    .font(Typography.headline)
                Text("×\(repetitions) — \(steps.count) step(s)")
                    .font(Typography.caption)
                    .foregroundStyle(Colors.secondaryText)
            }
        }
    }

    private func summary(for step: SegmentStep) -> String {
        var parts = [goalSummary(step.goal)]
        if let target = step.target {
            parts.append(targetSummary(target))
        }
        return parts.joined(separator: " · ")
    }

    private func goalSummary(_ goal: Goal) -> String {
        switch goal {
        case let .distance(meters):
            return UnitFormatter.segmentDistanceString(meters: meters, unit: displayUnit)
        case let .duration(seconds):
            return UnitFormatter.durationString(seconds: seconds)
        case .open:
            return "Open"
        }
    }

    private func targetSummary(_ target: Target) -> String {
        switch target {
        case let .pace(range):
            // `Target.pace`'s lower bound is the faster (smaller s/m) pace,
            // so this reads left-to-right as fastest-to-slowest.
            let fastest = UnitFormatter.paceString(secondsPerMeter: range.lowerBound, unit: displayUnit)
            let slowest = UnitFormatter.paceString(secondsPerMeter: range.upperBound, unit: displayUnit)
            return "\(fastest)–\(slowest)"
        case .heartRate:
            return "Heart rate target"
        case .cadence:
            return "Cadence target"
        }
    }
}
