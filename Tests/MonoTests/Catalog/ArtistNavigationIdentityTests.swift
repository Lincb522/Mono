import XCTest
@testable import Mono

final class ArtistNavigationIdentityTests: XCTestCase {
    func testSameNumericIDOnDifferentPlatformsIsNotTheSameDestination() {
        let jay = artist(id: 4558, name: "周杰伦", source: .qqmusic, qqMid: "0025NhlN2yWrP4")
        let ma = artist(id: 4558, name: "马洪波", source: .netease)
        let destinations: Set<LibraryViewModel.NavigationDestination> = [
            .artistInfo(jay), .artistInfo(ma)
        ]
        XCTAssertEqual(destinations.count, 2)
    }

    func testQCMUsesMIDWhenNumericIDIsUnavailableOrShared() {
        let jay = artist(id: 0, source: .qqmusic, qqMid: "0025NhlN2yWrP4")
        let jj = artist(id: 0, source: .qqmusic, qqMid: "001BLpXF2DyJe2")
        XCTAssertNotEqual(destination(jay), destination(jj))
    }

    func testSameMIDRemainsTheSameDestinationAfterMetadataRefresh() {
        let first = artist(id: 0, name: "Jay Chou", source: .qqmusic, qqMid: "0025NhlN2yWrP4")
        let refreshed = artist(id: 4558, name: "周杰伦", source: .qqmusic, qqMid: "0025NhlN2yWrP4")
        XCTAssertEqual(destination(first), destination(refreshed))
        XCTAssertEqual(Set([destination(first), destination(refreshed)]).count, 1)
    }

    func testLegacyArtistsKeepNCMIdentity() {
        let legacy = artist(id: 4558)
        let explicit = artist(id: 4558, source: .netease)
        XCTAssertEqual(destination(legacy), destination(explicit))
    }

    func testQCMWithoutMIDDoesNotCollideWithNCM() {
        let ncm = artist(id: 4558, source: .netease)
        XCTAssertNotEqual(destination(artist(id: 4558, source: .qqmusic)), destination(ncm))
        XCTAssertNotEqual(destination(artist(id: 4558, source: .qqmusic, qqMid: "")), destination(ncm))
    }

    private func destination(_ artist: ArtistInfo) -> LibraryViewModel.NavigationDestination {
        .artistInfo(artist)
    }

    private func artist(
        id: Int,
        name: String = "Artist",
        source: MusicSource? = nil,
        qqMid: String? = nil
    ) -> ArtistInfo {
        ArtistInfo(
            id: id, name: name, picUrl: nil, img1v1Url: nil, cover: nil, avatar: nil,
            musicSize: nil, albumSize: nil, mvSize: nil, briefDesc: nil, alias: nil,
            followed: nil, accountId: nil, source: source, qqMid: qqMid
        )
    }
}
