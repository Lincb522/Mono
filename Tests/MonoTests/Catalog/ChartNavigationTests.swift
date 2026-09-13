import XCTest
@testable import Mono

@MainActor
final class ChartNavigationTests: XCTestCase {
    func testQCMSelectionDisplaysQCMChartsInsteadOfCachedNCMCharts() {
        let model = LibraryViewModel()
        model.topLists = [chart(id: 4, name: "NCM", source: .netease)]
        model.qqTopLists = [QQTopListGroup(groupId: 0, groupName: "QCM", items: [
            QQTopListItem(topId: 4, title: "QCM", coverUrl: nil, intro: "", period: "", updateTime: "每日更新")
        ])]
        model.chartsSource = .qq
        XCTAssertEqual(model.displayedTopLists.map(\.name), ["QCM"])
        XCTAssertEqual(model.displayedTopLists.first?.source, .qqmusic)
    }

    func testUnloadedQCMAndAMChartsNeverDisplayNCMData() {
        let model = LibraryViewModel()
        model.topLists = [chart(id: 4, name: "NCM", source: .netease)]
        model.chartsSource = .qq
        XCTAssertTrue(model.displayedTopLists.isEmpty)
        model.chartsSource = .appleMusic
        XCTAssertTrue(model.displayedTopLists.isEmpty)
    }

    func testAMChartKeepsCatalogIDThroughPlaylistConversionAndCoding() throws {
        let model = LibraryViewModel()
        let top = TopList(id: 4, name: "Top 100", coverImgUrl: nil, updateFrequency: "Daily",
                          source: .appleMusic, appleMusicID: "pl.top100-global")
        model.appleMusicTopLists = [top]
        model.chartsSource = .appleMusic
        let selected = try XCTUnwrap(model.displayedTopLists.first)
        let restored = try JSONDecoder().decode(TopList.self, from: JSONEncoder().encode(selected))
        let playlist = restored.playlist()
        XCTAssertEqual(playlist.source, .appleMusic)
        XCTAssertEqual(playlist.appleMusicID, "pl.top100-global")
        XCTAssertTrue(playlist.isTopList)
    }

    func testLoadingStateBelongsToSelectedSource() {
        let model = LibraryViewModel()
        model.isLoadingCharts = true
        model.chartsSource = .qq
        XCTAssertFalse(model.isLoadingDisplayedCharts)
        model.isLoadingQQCharts = true
        XCTAssertTrue(model.isLoadingDisplayedCharts)
        model.chartsSource = .appleMusic
        XCTAssertFalse(model.isLoadingDisplayedCharts)
        model.isLoadingAppleMusicCharts = true
        XCTAssertTrue(model.isLoadingDisplayedCharts)
    }

    func testChartNavigationSeparatesPlatformsAndOrdinaryPlaylists() {
        let ncm = chart(id: 4, name: "NCM", source: .netease).playlist()
        let qq = chart(id: 4, name: "QCM", source: .qqmusic).playlist()
        var ordinaryQQ = qq
        ordinaryQQ.isTopList = false
        let destinations: Set<LibraryViewModel.NavigationDestination> = [
            .playlist(ncm), .playlist(qq), .playlist(ordinaryQQ)
        ]
        XCTAssertEqual(destinations.count, 3)
    }

    func testAMNavigationUsesCatalogIDInsteadOfSyntheticNumericID() {
        let first = TopList(id: 4, name: "First", coverImgUrl: nil, updateFrequency: "",
                            source: .appleMusic, appleMusicID: "pl.first").playlist()
        let other = TopList(id: 4, name: "Other", coverImgUrl: nil, updateFrequency: "",
                            source: .appleMusic, appleMusicID: "pl.other").playlist()
        XCTAssertNotEqual(LibraryViewModel.NavigationDestination.playlist(first), .playlist(other))
    }

    func testLegacyNCMAndKCMChartsPreserveTheirIdentifiers() throws {
        let data = Data(#"{"id":4,"name":"Legacy","updateFrequency":"Daily"}"#.utf8)
        let legacy = try JSONDecoder().decode(TopList.self, from: data)
        XCTAssertNil(legacy.appleMusicID)
        XCTAssertEqual(legacy.playlist().navigationIdentity, "netease:chart:4")
        let kcm = TopList(id: 4, name: "KCM", coverImgUrl: nil, updateFrequency: "",
                          source: .kugou, kugouID: "kcm-chart").playlist()
        XCTAssertEqual(kcm.kugouID, "kcm-chart")
        XCTAssertEqual(kcm.source, .kugou)
    }

    private func chart(id: Int, name: String, source: MusicSource) -> TopList {
        TopList(id: id, name: name, coverImgUrl: nil, updateFrequency: "", source: source)
    }
}
