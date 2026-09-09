import Foundation

struct AudioTrainingModelInstallDescriptor: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var version: String
    var sha256: String
    var byteCount: Int
    var featureSchemaVersion: Int
    var targetSchemaVersion: Int
    var completeSampleCount: Int
    var legacySampleCount: Int
    var learningConditionedSampleCount: Int
    var deviceConditionedSampleCount: Int
    var completeAccountCount: Int = 0
    var completeBranchSampleCounts: [String: Int] = [:]
    var completeBranchAccountCounts: [String: Int] = [:]
    var qualityWarnings: [String] = []

    var createdAt: String? = nil
    var fileName: String? = nil
    var release: AudioTrainingModelRelease? = nil

    var displayName: String { AudioTrainingModelPresentation.name(version: version, createdAt: createdAt) }
    var downloadFileName: String {
        if let fileName, fileName.count <= 160, fileName.hasSuffix(".mlmodel"),
           fileName.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_. ").contains($0) }) {
            return fileName
        }
        return AudioTrainingModelPresentation.fileName(version: version, createdAt: createdAt)
    }

    var distributionIdentity: String { "\(id):\(sha256)" }

    func validateDistribution() throws {
        let identifierCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !id.isEmpty, id.count <= 160,
              id.unicodeScalars.allSatisfy({ identifierCharacters.contains($0) }),
              version.hasPrefix("mono-resonance-s2-"),
              featureSchemaVersion == 7, targetSchemaVersion == 4,
              (1...536_870_912).contains(byteCount),
              sha256.count == 64, sha256.allSatisfy(\.isHexDigit) else {
            throw AIResonanceDistributionError.invalidModel
        }
    }
}

struct AIResonanceConfiguration: Codable, Equatable, Sendable {
    var enabled: Bool
    var model: AudioTrainingModelInstallDescriptor?
}

struct AIResonanceConfigurationUpdate: Encodable, Sendable {
    var enabled: Bool
    var modelID: String
}

struct AIResonanceModelList: Decodable, Sendable {
    var models: [AudioTrainingModelInstallDescriptor]
}

enum AIResonanceDistributionError: LocalizedError {
    case invalidModel
    case modelUnavailable
    case downloadFailed(Int)
    case installationInProgress

    var errorDescription: String? {
        switch self {
        case .invalidModel: return String(localized: "ai_resonance_invalid_model")
        case .modelUnavailable: return String(localized: "ai_resonance_model_unavailable")
        case let .downloadFailed(status):
            return String(format: String(localized: "ai_resonance_download_failed"), status)
        case .installationInProgress: return String(localized: "ai_resonance_install_busy")
        }
    }
}

struct AudioTrainingModelRelease: Codable, Equatable, Sendable {
    var publishedAt: String
    var summary: String
    var notes: String?
    var changelog: String
    var generatedAutomatically: Bool? = nil

    var publicationDateText: String { AudioTrainingModelPresentation.dateText(publishedAt) }
}

enum AudioTrainingModelPresentation {
    static func name(version: String, createdAt: String? = nil) -> String {
        let title = String(format: String(localized: "ai_resonance_model_name_version"), versionText(version))
        guard let date = modelDate(version: version, createdAt: createdAt) else { return title }
        return String(format: String(localized: "ai_resonance_model_name_date"), title,
                      compactDateText(date))
    }

    static func versionText(_ version: String) -> String {
        let prefix = "mono-resonance-"
        guard version.hasPrefix(prefix) else { return version }
        let components = version.dropFirst(prefix.count).split(separator: "-")
        guard let family = components.first, family.first == "s", family.count > 1,
              family.dropFirst().allSatisfy(\.isNumber) else { return version }
        var revision = components.dropFirst().filter { component in
            !(component.hasPrefix("schema") && component.count > 6 && component.dropFirst(6).allSatisfy(\.isNumber))
        }
        if revision.count > 1, let timestamp = revision.first,
           timestamp.count == 14, timestamp.allSatisfy(\.isNumber) {
            revision.removeFirst()
        }
        let identifier = ([family.uppercased()] + revision.map(String.init)).joined(separator: "-")
        return String(format: String(localized: "ai_resonance_beta_version"), identifier)
    }

    static func fileName(version: String, createdAt: String? = nil) -> String {
        let family = version.hasPrefix("mono-resonance-s1-") ? "S1" : "S2"
        guard let date = modelDate(version: version, createdAt: createdAt) else {
            return "Mono-Resonance-\(family).mlmodel"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: date).replacingOccurrences(of: "T", with: "_")
            .replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "Z", with: "UTC")
        return "Mono-Resonance-\(family)_\(timestamp).mlmodel"
    }

    static func dateText(_ value: String) -> String {
        guard let date = parseDate(value) else { return String(localized: "ai_resonance_publication_date_unknown") }
        return compactDateText(date)
    }

    private static func compactDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMddHHmm")
        return formatter.string(from: date)
    }

    private static func modelDate(version: String, createdAt: String?) -> Date? {
        if let createdAt, let date = parseDate(createdAt) { return date }
        guard let component = version.split(separator: "-").first(where: {
            $0.count == 14 && $0.allSatisfy(\.isNumber)
        }) else { return nil }
        let digits = Array(component)
        let iso = "\(String(digits[0..<4]))-\(String(digits[4..<6]))-\(String(digits[6..<8]))T\(String(digits[8..<10])):\(String(digits[10..<12])):\(String(digits[12..<14]))Z"
        return parseDate(iso)
    }

    static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
