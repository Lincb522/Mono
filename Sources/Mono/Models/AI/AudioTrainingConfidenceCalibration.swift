import Foundation

/// Coverage of the model's EQ prediction against held-out reference targets,
/// before device correction and local learning. This is not listening quality.
struct AudioTrainingConfidenceEvidence: Codable, Equatable, Sendable {
    let method: String
    let branch: String
    let coverage: Double
    let radiusDB: Double
    let tracks: Int
    let quantileRank: Int

    var isValid: Bool {
        method == AudioTrainingConfidenceCalibration.method
            && coverage == 0.9 && radiusDB.isFinite && radiusDB >= 0
            && tracks >= 32 && quantileRank == Int(ceil((Double(tracks) + 1) * coverage))
            && quantileRank <= tracks
    }

    var displayText: String {
        String(format: String(localized: "audio_training_confidence_calibrated"),
               locale: Locale.current, Int(coverage * 100), ceil(radiusDB * 100) / 100)
    }
}

struct AudioTrainingConfidenceCalibration: Codable, Equatable, Sendable {
    static let method = "split-conformal-track-max-v1"

    struct Branch: Codable, Equatable, Sendable {
        let status: String
        let unresolvedTrackSamples: Int?
        let samples: Int
        let tracks: Int
        let quantileRank: Int
        let radiusDB: Double?
        let trackCorrectionStrength: Double
    }

    let schemaVersion: Int
    let method: String
    let scope: String
    let coverage: Double
    let unresolvedTrackSamples: Int?
    let numericalMarginDB: Double?
    let minimumTracks: Int
    let trainingTracks: Int
    let selectionTracks: Int
    let calibrationTracks: Int
    let branches: [String: Branch]

    func evidence(for branch: String, trackCorrectionStrength: Float) -> AudioTrainingConfidenceEvidence? {
        guard schemaVersion == 1, method == Self.method, scope == "graphic-eq-reference",
              minimumTracks >= 32, let value = branches[branch], value.status == "calibrated",
              (value.unresolvedTrackSamples ?? unresolvedTrackSamples ?? 0) == 0,
              value.samples >= value.tracks, value.tracks >= minimumTracks,
              calibrationTracks >= value.tracks, trainingTracks > 0,
              value.trackCorrectionStrength.isFinite,
              abs(value.trackCorrectionStrength - Double(trackCorrectionStrength)) < 0.000_001,
              let radius = value.radiusDB else { return nil }
        let result = AudioTrainingConfidenceEvidence(
            method: method, branch: branch, coverage: coverage, radiusDB: radius,
            tracks: value.tracks, quantileRank: value.quantileRank
        )
        return result.isValid ? result : nil
    }
}
