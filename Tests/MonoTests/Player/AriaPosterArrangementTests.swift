import XCTest
@testable import Mono

@MainActor
final class AriaPosterArrangementTests: XCTestCase {
    func testSameSongKeepsArrangementAcrossRecreationAndSeeking() {
        let first = AriaPosterArrangement(songIdentity: "netease:100")
        let replay = AriaPosterArrangement(songIdentity: "netease:100")
        XCTAssertEqual(first.direction, replay.direction)
        XCTAssertEqual(first.wallRows, replay.wallRows)
        XCTAssertEqual(first.columns, replay.columns)
        XCTAssertEqual(first.phraseRows, replay.phraseRows)
        XCTAssertEqual(first.travelSpeed, replay.travelSpeed)
        for index in [8, 2, 19, 0, 8, Int.min, Int.max] {
            XCTAssertEqual(first.choice(for: index, count: 3), replay.choice(for: index, count: 3))
            XCTAssertTrue((0..<3).contains(first.choice(for: index, count: 3)))
        }
    }

    func testDifferentSongIdentitiesProduceDifferentSequences() {
        let signatures = (0..<32).map { song in
            let arrangement = AriaPosterArrangement(songIdentity: "test-song-\(song)")
            return (0..<24).map { String(arrangement.choice(for: $0, count: 3)) }.joined()
        }
        XCTAssertEqual(Set(signatures).count, signatures.count)
    }

    func testDensityAndSpeedStayBounded() {
        for song in 0..<64 {
            let arrangement = AriaPosterArrangement(songIdentity: "test-song-\(song)")
            XCTAssertTrue((8...12).contains(arrangement.wallRows))
            XCTAssertTrue((3...5).contains(arrangement.columns))
            XCTAssertTrue((3...4).contains(arrangement.phraseRows))
            XCTAssertTrue((16...32).contains(arrangement.travelSpeed))
        }
    }
    func testEveryRoundUsesAllCompositionsAndRespectsCooldown() {
        let count = AriaPosterComposition.allCases.count
        for song in 0..<32 {
            let arrangement = AriaPosterArrangement(songIdentity: "test-song-\(song)")
            let sequence = (0..<(count * 12)).map { arrangement.composition(at: $0) }
            for start in stride(from: 0, to: sequence.count, by: count) {
                XCTAssertEqual(Set(sequence[start..<(start + count)]).count, count)
            }
            for index in sequence.indices {
                let recent = sequence[max(0, index - 10)..<index]
                XCTAssertFalse(recent.contains(sequence[index]))
            }
        }
    }

    func testCompositionIsStableAcrossSeekingAndVariesBySong() {
        let first = AriaPosterArrangement(songIdentity: "first-song")
        let replay = AriaPosterArrangement(songIdentity: "first-song")
        for ordinal in [80, 3, 44, 0, 80] {
            XCTAssertEqual(first.composition(at: ordinal), replay.composition(at: ordinal))
        }
        let signatures = (0..<32).map { song in
            let arrangement = AriaPosterArrangement(songIdentity: "song-\(song)")
            return (0..<27).map { String(arrangement.composition(at: $0).rawValue) }.joined()
        }
        XCTAssertEqual(Set(signatures).count, 32)
    }

    func testRepeatedEffectsUseDifferentInternalVariations() {
        let arrangement = AriaPosterArrangement(songIdentity: "repeated-chorus")
        var seen: [AriaPosterComposition: Set<Int>] = [:]
        for index in 0..<(AriaPosterComposition.allCases.count * 4) {
            let scene = arrangement.scene(at: index)
            XCTAssertTrue((0..<4).contains(scene.variation))
            XCTAssertFalse(seen[scene.composition, default: []].contains(scene.variation))
            seen[scene.composition, default: []].insert(scene.variation)
        }
        XCTAssertEqual(seen.count, 21)
        XCTAssertTrue(seen.values.allSatisfy { $0.count == 4 })
    }

    func testCacheChurnDoesNotChangeSongChoreography() {
        let identity = "cache-recreated-song"
        let initial = AriaPosterArrangement(songIdentity: identity)
        let expected = (0..<120).map { initial.scene(at: $0) }
        for index in 0..<100 {
            _ = AriaPosterArrangement(songIdentity: "cache-churn-\(index)").scene(at: 60)
        }
        let recreated = AriaPosterArrangement(songIdentity: identity)
        for index in [119, 0, 61, 20, 119] {
            XCTAssertEqual(recreated.scene(at: index), expected[index])
        }
    }

}
