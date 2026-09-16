import AVFoundation
import Combine
import XCTest
@testable import Mono

@MainActor
final class BloudMetadataTests: XCTestCase {
    func testEmbeddedNumericGenreMetadataUsesTheCorrectIndexBase() async {
        let id3 = AVMutableMetadataItem()
        id3.identifier = .id3MetadataContentType
        id3.value = "(17)" as NSString
        let mp4 = AVMutableMetadataItem()
        mp4.identifier = .iTunesMetadataPredefinedGenre
        mp4.value = NSNumber(value: 9)
        let tags = await SongGenreMetadata.localTags(in: [id3, mp4])
        XCTAssertEqual(tags, ["Rock", "Jazz"])
        XCTAssertEqual(BloudTagExpression.resolve(tags), .excited)

        let binary = AVMutableMetadataItem()
        binary.identifier = .iTunesMetadataPredefinedGenre
        binary.value = Data([0, 18]) as NSData
        let binaryTags = await SongGenreMetadata.localTags(in: [binary])
        XCTAssertEqual(binaryTags, ["Rock"])
    }

    func testID3NumericReferencesPreserveTextAndRejectUnknownCodes() {
        XCTAssertEqual(SongGenreMetadata.id3Tags("17"), ["Rock"])
        XCTAssertEqual(SongGenreMetadata.id3Tags("(17)(13)"), ["Rock", "Pop"])
        XCTAssertEqual(SongGenreMetadata.id3Tags("(17)Indie Rock"), ["Rock", "Indie Rock"])
        XCTAssertEqual(SongGenreMetadata.predefinedGenre(18), ["Rock"])
        XCTAssertTrue(SongGenreMetadata.id3Tags("255").isEmpty)
        XCTAssertTrue(SongGenreMetadata.predefinedGenre(0).isEmpty)
        XCTAssertTrue(SongGenreMetadata.predefinedGenre(Int.max).isEmpty)
    }

    func testNeteaseReadsCatalogTagsAndIgnoresRecommendationContent() throws {
        // Public song 186016, /api/song/play/about/block/page, captured 2026-09-14.
        let data = Data(#"""
        {"data":{"blocks":[
          {"code":"SONG_PLAY_ABOUT_SONG_BASIC","creatives":[
            {"creativeType":"songTag","resources":[{"uiElement":{"mainTitle":{"title":"流行-华语流行"}}}]},
            {"creativeType":"songBizTag","resources":[{"uiElement":{"mainTitle":{"title":"思念"}}}]},
            {"creativeType":"description","resources":[{"uiElement":{"mainTitle":{"title":"Metal"}}}]}
          ]},
          {"code":"RELATED_PLAYLIST","creatives":[
            {"creativeType":"songTag","resources":[{"uiElement":{"mainTitle":{"title":"Metal"}}}]}
          ]}
        ]}}
        """#.utf8)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tags = SongGenreMetadata.neteaseTags(in: body)
        XCTAssertEqual(tags, ["流行-华语流行", "思念"])
        XCTAssertEqual(BloudTagExpression.resolve(tags), .shy)
    }

    func testOptionalGenresSurvivePersistenceWithoutChangingSongIdentity() throws {
        var original = try song(id: 1, source: .netease)
        XCTAssertNil(original.genreTags)
        original.genreTags = ["Jazz", "爵士"]
        let restored = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.genreTags, original.genreTags)
        XCTAssertEqual(restored.identityKey, original.identityKey)
    }

    func testInlineTagsLockPerTrackAndManualChoiceCanReturnToAutomatic() async throws {
        var requests = 0
        let model = BloudListeningModel(fetchTags: { _ in
            requests += 1
            return Just(["Electronic"]).setFailureType(to: Error.self).eraseToAnyPublisher()
        })
        var first = try song(id: 1, source: .netease)
        first.genreTags = ["Jazz"]
        await model.prepare(song: first)
        XCTAssertEqual(model.expression(for: first), .curious)
        XCTAssertEqual(requests, 0)

        first.genreTags = ["Metal"]
        await model.prepare(song: first)
        XCTAssertEqual(model.expression(for: first), .curious)
        model.select(.happy, for: first)
        XCTAssertEqual(model.expression(for: first), .happy)
        model.select(nil, for: first)
        XCTAssertEqual(model.expression(for: first), .curious)

        let otherSource = try song(id: 1, source: .qqmusic)
        await model.prepare(song: otherSource)
        XCTAssertEqual(model.expression(for: otherSource), .excited)
        XCTAssertEqual(requests, 1)
    }

    func testLateMetadataFromPreviousSourceCannotOverrideCurrentTrack() async throws {
        let pending = PassthroughSubject<[String], Error>()
        let subscribed = expectation(description: "Metadata request subscribed")
        let model = BloudListeningModel(fetchTags: { _ in
            pending.handleEvents(receiveSubscription: { _ in subscribed.fulfill() })
                .eraseToAnyPublisher()
        })
        let previous = try song(id: 9, source: .netease)
        let oldTask = Task { await model.prepare(song: previous) }
        await fulfillment(of: [subscribed], timeout: 1)

        var current = try song(id: 9, source: .qqmusic)
        current.genreTags = ["Hip-Hop/Rap"]
        await model.prepare(song: current)
        pending.send(["Metal"])
        pending.send(completion: .finished)
        await oldTask.value
        XCTAssertEqual(model.expression(for: current), .proud)
        XCTAssertEqual(model.expression(for: previous), .calm)
        XCTAssertEqual(model.pawExpression(for: current), .proud)
        XCTAssertEqual(model.pawExpression(for: previous), .soft)
    }

    func testMissingTagsDoNotLockOutLaterMetadataForTheSameTrack() async throws {
        let model = BloudListeningModel(fetchTags: { _ in
            Just(["国语"]).setFailureType(to: Error.self).eraseToAnyPublisher()
        })
        var current = try song(id: 12, source: .netease)
        await model.prepare(song: current)
        XCTAssertNil(model.automaticExpression)
        XCTAssertEqual(model.expression(for: current), .calm)

        current.genreTags = ["Metal"]
        await model.prepare(song: current)
        XCTAssertEqual(model.expression(for: current), .angry)
    }

    func testCompanionsKeepIndependentManualAndAutomaticExpressions() async throws {
        let model = BloudListeningModel(fetchTags: { _ in
            Just(["Pop"]).setFailureType(to: Error.self).eraseToAnyPublisher()
        })
        var current = try song(id: 31, source: .netease)
        current.genreTags = ["Sad"]
        await model.prepare(song: current)
        XCTAssertEqual(model.expression(for: current), .sad)
        XCTAssertEqual(model.pawExpression(for: current), .pout)
        XCTAssertEqual(model.catExpression(for: current), .pout)
        model.selectCat(.cozy, for: current)
        model.selectPaw(.blep, for: current)
        XCTAssertEqual(model.catExpression(for: current), .cozy)
        XCTAssertEqual(model.expression(for: current), .sad)
        model.select(.curious, for: current)
        XCTAssertEqual(model.pawExpression(for: current), .blep)
        model.selectCat(nil, for: current)
        XCTAssertEqual(model.catExpression(for: current), .pout)
        XCTAssertEqual(model.pawExpression(for: current), .blep)
        model.selectCat(.wink, for: current)
        model.selectPaw(nil, for: current)
        XCTAssertEqual(model.pawExpression(for: current), .pout)
        XCTAssertEqual(model.expression(for: current), .curious)
        let next = try song(id: 32, source: .netease)
        await model.prepare(song: next)
        XCTAssertNil(model.manualPawExpression)
        XCTAssertNil(model.manualCatExpression)
        XCTAssertEqual(model.catExpression(for: next), .bright)
        XCTAssertNil(model.manualExpression)
        XCTAssertEqual(model.pawExpression(for: next), .bright)
        XCTAssertEqual(model.expression(for: next), .happy)
    }

    private func song(id: Int, source: MusicSource) throws -> Song {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "name": "Fixture"])
        var song = try JSONDecoder().decode(Song.self, from: data)
        song.source = source
        return song
    }
}
