import Foundation

/// Shared presentation rules; series percentages represent episode counts, not a seek position.
public extension BaseItem {
    var resumePositionSeconds: Double {
        guard type != "Series", userData?.played != true else { return 0 }
        return max(0, Double(userData?.playbackPositionTicks ?? 0) / 10_000_000)
    }

    var viewingProgress: Double? {
        guard userData?.played != true else { return nil }
        if let percentage = userData?.playedPercentage, percentage > 0 {
            return min(1, max(0, percentage / 100))
        }
        let duration = Double(runTimeTicks ?? 0) / 10_000_000
        guard duration > 0, resumePositionSeconds > 0 else { return nil }
        return min(1, resumePositionSeconds / duration)
    }

    var viewingStatus: String {
        if userData?.played == true { return "Watched" }
        if type == "Series", let remaining = userData?.unplayedItemCount {
            return "\(remaining) unwatched episode\(remaining == 1 ? "" : "s")"
        }
        if resumePositionSeconds > 0 { return "In progress · \(resumeTimestamp)" }
        return "Unwatched"
    }

    var resumeTimestamp: String {
        let seconds = Int(resumePositionSeconds)
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var playbackActionTitle: String {
        let action = resumePositionSeconds > 0 ? "Resume" : "Play"
        guard type == "Episode" else {
            return resumePositionSeconds > 0 ? "Resume · \(resumeTimestamp)" : action
        }
        let code = (parentIndexNumber.map { String(format: "S%d", $0) } ?? "")
            + (indexNumber.map { String(format: " E%d", $0) } ?? "")
        return code.isEmpty ? action : "\(action) \(code.trimmingCharacters(in: .whitespaces))"
    }
}
