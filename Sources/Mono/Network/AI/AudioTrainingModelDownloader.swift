import Foundation

enum AudioTrainingModelDownloader {
    static func download(
        _ descriptor: AudioTrainingModelInstallDescriptor,
        request: URLRequest
    ) async throws -> Data {
        try descriptor.validateDistribution()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        let delegate = DownloadDelegate(byteLimit: Int64(descriptor.byteCount))
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            throw AIResonanceDistributionError.downloadFailed(http.statusCode)
        }
        guard http.value(forHTTPHeaderField: "X-Mono-Model-SHA256")?.lowercased() == descriptor.sha256.lowercased(),
              http.value(forHTTPHeaderField: "X-Mono-Model-Version") == descriptor.version,
              Int(http.value(forHTTPHeaderField: "X-Mono-Feature-Schema") ?? "") == descriptor.featureSchemaVersion,
              Int(http.value(forHTTPHeaderField: "X-Mono-Target-Schema") ?? "") == descriptor.targetSchemaVersion,
              (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize == descriptor.byteCount else {
            throw AIResonanceDistributionError.invalidModel
        }
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        let byteLimit: Int64

        init(byteLimit: Int64) { self.byteLimit = byteLimit }

        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            // Model downloads stay on the authenticated service origin.
            completionHandler(nil)
        }

        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            if totalBytesWritten > byteLimit || totalBytesExpectedToWrite > byteLimit {
                downloadTask.cancel()
            }
        }

        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {}
    }
}
