import SwiftUI
import Combine
@preconcurrency import QQMusicKit

extension LibraryViewModel {
    func fetchAppleMusicTopLists() {
        guard appleMusicTopLists.isEmpty, !appleChartsRequest.isRunning else { return }
        let request = appleChartsRequest.begin()
        isLoadingAppleMusicCharts = true
        appleChartsRequest.task = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            defer {
                if self.appleChartsRequest.isCurrent(request) {
                    self.appleChartsRequest.finish(request)
                    self.isLoadingAppleMusicCharts = false
                }
            }
            do {
                let lists = try await AppleMusicService.shared.topLists()
                guard !Task.isCancelled, self.appleChartsRequest.isCurrent(request) else { return }
                self.appleMusicTopLists = lists
            } catch {
                guard !Task.isCancelled, self.appleChartsRequest.isCurrent(request) else { return }
                AppLogger.warning("[AppleMusic] 榜单获取失败: \(error.localizedDescription)")
            }
        }
    }

    func fetchTopLists() {
        guard topLists.isEmpty, !chartsRequest.isRunning else { return }
        let request = chartsRequest.begin()
        isLoadingCharts = true
        chartsRequest.task = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let cached = await OptimizedCacheManager.shared.getObjectAsync(
                forKey: "top_charts_lists", type: [TopList].self
            )
            guard let self, !Task.isCancelled, self.chartsRequest.isCurrent(request) else { return }
            if let cached, !cached.isEmpty {
                self.topLists = cached
                self.isLoadingCharts = false
                self.chartsRequest.finish(request)
                return
            }

            self.chartsRequest.cancellable = self.apiService.fetchTopLists()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] _ in
                    guard let self, self.chartsRequest.isCurrent(request) else { return }
                    self.chartsRequest.finish(request)
                    self.isLoadingCharts = false
                }, receiveValue: { [weak self] lists in
                    guard let self, self.chartsRequest.isCurrent(request) else { return }
                    self.topLists = lists
                    OptimizedCacheManager.shared.setObject(lists, forKey: "top_charts_lists")
                })
        }
    }

    func fetchKugouTopLists() {
        guard kugouTopLists.isEmpty, !kugouChartsRequest.isRunning else { return }
        let request = kugouChartsRequest.begin()
        isLoadingKugouCharts = true
        kugouChartsRequest.task = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let cached = await OptimizedCacheManager.shared.getObjectAsync(
                forKey: "kcm_top_charts", type: [TopList].self
            )
            guard let self, !Task.isCancelled, self.kugouChartsRequest.isCurrent(request) else { return }
            if let cached, !cached.isEmpty {
                self.kugouTopLists = cached
                self.isLoadingKugouCharts = false
                self.kugouChartsRequest.finish(request)
                return
            }

            self.kugouChartsRequest.cancellable = self.apiService.fetchKugouTopLists()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] completion in
                    guard let self, self.kugouChartsRequest.isCurrent(request) else { return }
                    self.kugouChartsRequest.finish(request)
                    self.isLoadingKugouCharts = false
                    if case .failure(let error) = completion {
                        AppLogger.warning("KCM 榜单获取失败: \(error)")
                    }
                }, receiveValue: { [weak self] lists in
                    guard let self, self.kugouChartsRequest.isCurrent(request) else { return }
                    self.kugouTopLists = lists
                    OptimizedCacheManager.shared.setObject(lists, forKey: "kcm_top_charts")
                })
        }
    }

}
