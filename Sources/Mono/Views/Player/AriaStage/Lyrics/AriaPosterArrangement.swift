import SwiftUI
import CryptoKit

enum AriaPosterComposition: Int, CaseIterable {
    case punch, phrases, echo, wall, matrix, quiet, split, ribbon, focus
    case scatter, staircase, shutters, mosaic, rail, pivot, orbit
    case brackets, tunnel, margin, accordion, spotlight

    /// Similar visual grammars should not cluster even when effect names differ.
    var family: Int {
        switch self {
        case .punch, .quiet, .focus: return 0
        case .phrases, .ribbon, .staircase: return 1
        case .echo, .wall, .matrix: return 2
        case .split, .shutters, .spotlight: return 3
        case .scatter, .mosaic: return 4
        case .rail, .orbit, .margin: return 5
        case .pivot, .accordion: return 6
        case .brackets, .tunnel: return 7
        }
    }
}

struct AriaPosterScene: Equatable {
    let composition: AriaPosterComposition
    let variation: Int
}

/// Song-seeded choreography; cached separately from the per-frame render clock.
@MainActor
struct AriaPosterArrangement {
    private let bytes: [UInt8]
    private let schedule: AriaPosterSchedule

    init(songIdentity: String) {
        let schedule = AriaPosterScheduleCache.schedule(for: songIdentity)
        self.schedule = schedule
        bytes = schedule.bytes
    }

    var direction: CGFloat { bytes[0].isMultiple(of: 2) ? 1 : -1 }
    var phraseRows: Int { 3 + Int(bytes[1] % 2) }
    var wallRows: Int { 8 + Int(bytes[2] % 5) }
    var columns: Int { 3 + Int(bytes[3] % 3) }
    var travelSpeed: Double { 16 + Double(bytes[4] % 17) }

    func choice(for lineID: Int, count: Int) -> Int {
        let index = Int(lineID.magnitude % UInt(bytes.count))
        let section = Int((lineID.magnitude / UInt(bytes.count)) % UInt(count))
        return (Int(bytes[index]) + section) % count
    }

    func scene(at ordinal: Int) -> AriaPosterScene { schedule.scene(at: max(0, ordinal)) }
    func composition(at ordinal: Int) -> AriaPosterComposition { scene(at: ordinal).composition }
}

/// Build only the missing tail, not the whole song on every animation frame.
/// Least-used effects win, ten recent effects are excluded, and related families
/// are ranked behind distinct families. Replaying repeated lyrics doesn't reset this.
@MainActor
private final class AriaPosterSchedule {
    let bytes: [UInt8]
    private var state: UInt64
    private var scenes: [AriaPosterScene] = []
    private var uses = Array(repeating: 0, count: AriaPosterComposition.allCases.count)
    private var recent: [AriaPosterComposition] = []

    init(songIdentity: String) {
        bytes = Array(SHA256.hash(data: Data(songIdentity.utf8)))
        state = bytes.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    func scene(at ordinal: Int) -> AriaPosterScene {
        while scenes.count <= ordinal {
            let candidates = AriaPosterComposition.allCases.filter { !recent.contains($0) }
            // There are 21 compositions and only ten excluded, so this set is nonempty.
            var selected = candidates[0]
            var bestScore = Int.max
            for candidate in candidates {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let related = recent.suffix(2).filter { $0.family == candidate.family }.count
                let score = uses[candidate.rawValue] * 10_000 + related * 1_000
                    + Int((state >> 32) % 997)
                if score < bestScore {
                    selected = candidate
                    bestScore = score
                }
            }
            let variation = (uses[selected.rawValue] + Int(bytes[selected.rawValue % bytes.count] % 4)) % 4
            scenes.append(AriaPosterScene(composition: selected, variation: variation))
            uses[selected.rawValue] += 1
            recent.append(selected)
            if recent.count > 10 { recent.removeFirst() }
        }
        return scenes[ordinal]
    }
}

@MainActor
private enum AriaPosterScheduleCache {
    static let storage: NSCache<NSString, AriaPosterSchedule> = {
        let cache = NSCache<NSString, AriaPosterSchedule>()
        cache.countLimit = 24
        return cache
    }()

    static func schedule(for identity: String) -> AriaPosterSchedule {
        let key = identity as NSString
        if let existing = storage.object(forKey: key) { return existing }
        let schedule = AriaPosterSchedule(songIdentity: identity)
        storage.setObject(schedule, forKey: key)
        return schedule
    }
}
