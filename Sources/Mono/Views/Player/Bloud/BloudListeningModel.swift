import Combine
import Foundation

/// Catalog tags select the expression once; PCM only animates its eyelids.
@MainActor
final class BloudListeningModel: ObservableObject {
    static let shared = BloudListeningModel()
    @Published private(set) var manualExpression: BloudExpression?
    @Published private(set) var automaticExpression: BloudExpression?
    @Published private(set) var manualCatExpression: PawExpression?
    @Published private(set) var manualPawExpression: PawExpression?
    @Published private(set) var automaticPawExpression: PawExpression?
    private var trackIdentity: String?
    private var requestToken = UUID()
    private let fetchTags: @MainActor (Song) -> AnyPublisher<[String], Error>

    init(fetchTags: @escaping @MainActor (Song) -> AnyPublisher<[String], Error> = {
        APIService.shared.fetchSongGenreTags(song: $0)
    }) {
        self.fetchTags = fetchTags
    }

    func expression(for song: Song?) -> BloudExpression {
        guard trackIdentity == song?.identityKey else { return .calm }
        return manualExpression ?? automaticExpression ?? .calm
    }

    func select(_ expression: BloudExpression?, for song: Song?) {
        resetIfNeeded(for: song)
        manualExpression = expression
    }

    func pawExpression(for song: Song?) -> PawExpression {
        guard trackIdentity == song?.identityKey else { return .soft }
        return manualPawExpression ?? automaticPawExpression ?? .soft
    }

    func selectPaw(_ expression: PawExpression?, for song: Song?) {
        resetIfNeeded(for: song)
        manualPawExpression = expression
    }

    func catExpression(for song: Song?) -> PawExpression {
        guard trackIdentity == song?.identityKey else { return .soft }
        return manualCatExpression ?? automaticPawExpression ?? .soft
    }

    func selectCat(_ expression: PawExpression?, for song: Song?) {
        resetIfNeeded(for: song)
        manualCatExpression = expression
    }

    private func resetIfNeeded(for song: Song?) {
        guard trackIdentity != song?.identityKey else { return }
        trackIdentity = song?.identityKey
        automaticExpression = nil
        manualExpression = nil
        automaticPawExpression = nil
        manualPawExpression = nil
        manualCatExpression = nil
        requestToken = UUID()
    }

    /// Metadata is available independently of playback, PCM, and AI tuning.
    func prepare(song: Song?) async {
        resetIfNeeded(for: song)
        let token = UUID()
        requestToken = token
        guard let song, automaticExpression == nil || automaticPawExpression == nil else { return }
        if accept(song.genreTags ?? []) { return }
        do {
            let publisher = fetchTags(song).timeout(
                .seconds(10), scheduler: DispatchQueue.main,
                customError: { URLError(.timedOut) }
            )
            for try await tags in publisher.values {
                guard !Task.isCancelled, requestToken == token,
                      trackIdentity == song.identityKey else { return }
                if !accept(tags) {
                    AppLogger.debug("[Bloud] Some companions have no matching catalog tags for current track", step: "bloud.metadata")
                }
                return
            }
        } catch {
            guard !Task.isCancelled, requestToken == token else { return }
            AppLogger.debug("[Bloud] Song tags unavailable: \(error.localizedDescription)", step: "bloud.metadata")
        }
    }

    @discardableResult
    private func accept(_ tags: [String]) -> Bool {
        if automaticExpression == nil, let resolved = BloudTagExpression.resolve(tags) {
            automaticExpression = resolved
            AppLogger.debug("[Bloud] Catalog expression=\(resolved.rawValue)", step: "bloud.metadata")
        }
        if automaticPawExpression == nil, let resolved = PawTagExpression.resolve(tags) {
            automaticPawExpression = resolved
            AppLogger.debug("[PAW] Catalog expression=\(resolved.rawValue)", step: "bloud.metadata")
        }
        return automaticExpression != nil && automaticPawExpression != nil
    }
}
