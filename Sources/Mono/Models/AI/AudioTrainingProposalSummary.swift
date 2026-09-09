import Foundation

/// Describes the compiled plan, independently of how its numeric parameters were learned.
enum AudioTrainingProposalSummary {
    static let revision = "listening-summary-v1"

    static func make(
        bandFrequenciesHz: [Float],
        gains: [Float],
        tone: (bass: Float, treble: Float),
        enhancement: (enabled: Bool, vocal: Float, air: Float, deEss: Float, attack: Float, width: Float),
        spatial: (width: Float, surround: Float, reverb: Float),
        isSpatialProfile: Bool,
        protectsPeaks: Bool,
        controlsDynamics: Bool,
        bundle: Bundle = .main
    ) -> String {
        func text(_ suffix: String) -> String {
            bundle.localizedString(forKey: "audio_training_summary_" + suffix, value: nil, table: nil)
        }

        let bands = zip(bandFrequenciesHz, gains).filter {
            $0.0.isFinite && $0.1.isFinite && (30...16_000).contains($0.0)
        }
        // Ignore an effectively uniform level shift without inventing cuts in untouched bands.
        let levels = bands.map(\.1)
        let isUniform = (levels.max() ?? 0) - (levels.min() ?? 0) < 0.35
        let levelShift: Float = isUniform && !levels.isEmpty
            ? levels.reduce(0, +) / Float(levels.count) : 0
        func change(in range: ClosedRange<Float>) -> Float {
            let values = bands.filter { range.contains($0.0) }.map(\.1)
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Float(values.count) - levelShift
        }

        var changes: [(region: String, score: Float, key: String)] = []
        func add(_ region: String, _ score: Float, _ key: String) {
            guard score.isFinite, score >= 0.65 else { return }
            changes.append((region, score, key))
        }
        let bass = change(in: 30...250) + tone.bass
        let body = change(in: 300...1_000)
        let presence = change(in: 1_500...4_000)
        let treble = change(in: 5_000...16_000) + tone.treble
        add("bass", abs(bass), bass > 0 ? "bass_fuller" : "bass_tighter")
        add("body", abs(body), body > 0 ? "body_warmer" : "body_lighter")
        add("presence", abs(presence), presence > 0 ? "presence_forward" : "presence_softer")
        add("treble", abs(treble), treble > 0 ? "treble_brighter" : "treble_softer")
        if enhancement.enabled {
            add("presence", enhancement.vocal * 3, "presence_forward")
            add("treble", enhancement.air * 3, "treble_airier")
            add("treble", enhancement.deEss * 3, "treble_softer")
            add("transients", enhancement.attack * 3, "transients")
        }
        if controlsDynamics { add("dynamics", 1, "dynamics") }

        // Keep only the strongest description for a region, with stable ordering for ties.
        let ranked = changes.enumerated().sorted {
            $0.element.score == $1.element.score
                ? $0.offset < $1.offset
                : $0.element.score > $1.element.score
        }
        var regions = Set<String>()
        let selected = ranked.compactMap { entry -> String? in
            guard regions.insert(entry.element.region).inserted else { return nil }
            return text(entry.element.key)
        }.prefix(2)

        let tonalSentence: String
        if selected.count == 2 {
            tonalSentence = String(format: text("two_changes"), selected[selected.startIndex], selected[selected.index(after: selected.startIndex)])
        } else if let only = selected.first {
            tonalSentence = String(format: text("one_change"), only)
        } else {
            tonalSentence = text(protectsPeaks ? "neutral_protected" : "neutral")
        }

        let widened = spatial.width > 1.08 || spatial.surround > 0.15
            || (enhancement.enabled && enhancement.width > 0.2)
        let ambience = spatial.reverb > 0.12
        let spatialKey: String
        if isSpatialProfile {
            switch (widened, ambience) {
            case (true, true): spatialKey = "spatial_wide_ambience"
            case (true, false): spatialKey = "spatial_wide_dry"
            case (false, true): spatialKey = "spatial_ambience"
            case (false, false): spatialKey = "spatial_focused"
            }
        } else if spatial.width < 0.97 && spatial.surround < 0.05
                    && (!enhancement.enabled || enhancement.width < 0.1) {
            spatialKey = "standard_narrower"
        } else {
            spatialKey = widened ? "standard_wider" : "standard_preserved"
        }
        return String(format: text("sentences"), tonalSentence, text(spatialKey))
    }
}
