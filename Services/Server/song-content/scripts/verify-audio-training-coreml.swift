import CoreML
import Foundation

// Standalone macOS runtime check; does not build or launch the iOS application.
struct PredictionCase: Decodable {
    let input: [Double]
    let expected: [Double]
}

enum VerificationError: Error {
    case arguments
    case outputShape
    case calibrationMetadata
    case mismatch(test: Int, index: Int, expected: Double, actual: Double)
}

guard (3...4).contains(CommandLine.arguments.count) else { throw VerificationError.arguments }
let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
let casesURL = URL(fileURLWithPath: CommandLine.arguments[2])
let cases = try JSONDecoder().decode([PredictionCase].self, from: Data(contentsOf: casesURL))
let compiled = try MLModel.compileModel(at: modelURL)
defer { try? FileManager.default.removeItem(at: compiled) }
let configuration = MLModelConfiguration()
configuration.computeUnits = .cpuOnly
let model = try MLModel(contentsOf: compiled, configuration: configuration)
if CommandLine.arguments.count == 4 {
    let expectedData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
    let expected = try JSONSerialization.jsonObject(with: expectedData) as? NSDictionary
    let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
    guard let raw = metadata?["mono.confidence_calibration"], let data = raw.data(using: .utf8),
          let actual = try JSONSerialization.jsonObject(with: data) as? NSDictionary,
          let expected, actual == expected else { throw VerificationError.calibrationMetadata }
    print("Core ML runtime: calibration metadata preserved")
}
var maximumError = 0.0
for (testIndex, test) in cases.enumerated() {
    let input = try MLMultiArray(shape: [NSNumber(value: test.input.count)], dataType: .float32)
    for (index, value) in test.input.enumerated() { input[index] = NSNumber(value: value) }
    let provider = try MLDictionaryFeatureProvider(dictionary: ["features": MLFeatureValue(multiArray: input)])
    let result = try model.prediction(from: provider)
    guard let output = result.featureValue(for: "tuning")?.multiArrayValue,
          output.count == test.expected.count else { throw VerificationError.outputShape }
    for (index, expected) in test.expected.enumerated() {
        let actual = output[index].doubleValue
        let error = abs(actual - expected)
        guard actual.isFinite, error <= 0.0001 + abs(expected) * 0.0001 else {
            throw VerificationError.mismatch(test: testIndex, index: index, expected: expected, actual: actual)
        }
        maximumError = max(maximumError, error)
    }
}
print("Core ML runtime: \(cases.count) cases; maximum absolute error \(maximumError)")
