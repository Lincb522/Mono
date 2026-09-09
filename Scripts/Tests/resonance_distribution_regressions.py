#!/usr/bin/env python3
"""Exercise production configuration and downloads against a synthetic local service."""
import hashlib
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
PAYLOAD = bytes([31]) * 512
MODEL = dict(
    id="model-first", version="mono-resonance-s2-schema7-first",
    sha256=hashlib.sha256(PAYLOAD).hexdigest(), byteCount=len(PAYLOAD),
    featureSchemaVersion=7, targetSchemaVersion=4,
    completeSampleCount=64, legacySampleCount=0,
    learningConditionedSampleCount=8, deviceConditionedSampleCount=10,
    completeAccountCount=3, completeBranchSampleCounts={"tenBand:standard": 64},
    completeBranchAccountCounts={"tenBand:standard": 3}, qualityWarnings=[],
)
SECOND = {**MODEL, "id": "model-second", "version": "mono-resonance-s2-schema7-second"}
CONFIG = dict(
    schemaVersion=1, enabled=True, wireProtocol="openAICompatible", baseURL="",
    model="fixture-built-in", modelDiscoveryURL="", timeout=45, customHeadersJSON="", apiKey="",
    usageLimits=dict(dailyRequestLimit=50, hourlyRequestLimit=20, minimumRequestInterval=15),
    revision="fixture-initial", updatedAt=None,
    resonance=dict(enabled=True, model=MODEL),
)
STATS = dict(catalog=0, config=0, redirected=0, slow=0, downloads=0)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, code, body, headers=None):
        self.send_response(code)
        for key, value in (headers or {}).items():
            self.send_header(key, str(value))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def json(self, value, code=200):
        self.respond(code, json.dumps(value).encode(), {"Content-Type": "application/json"})

    def do_GET(self):
        if self.path == "/statistics":
            return self.json(STATS)
        if self.path == "/redirected":
            STATS["redirected"] += 1
            return self.json({})
        if self.path.endswith("/api/audio-training/models"):
            if self.headers.get("X-Admin-Token") != "fixture-admin":
                return self.json({"error": "unauthorized"}, 401)
            STATS["catalog"] += 1
            if STATS["catalog"] == 2:
                time.sleep(0.25)
                return self.json(dict(models=[MODEL]))
            return self.json(dict(models=[MODEL, SECOND]))
        if self.headers.get("X-Api-Token") != "fixture-user" or self.headers.get("X-Device-ID") != "fixture-device":
            return self.json({"error": "unauthorized"}, 401)
        if self.path.endswith("/public/ai/config"):
            STATS["config"] += 1
            time.sleep(0.05)
            return self.json(CONFIG)
        if self.path.endswith("/coreml"):
            STATS["downloads"] += 1
            descriptor = SECOND if "/model-second/" in self.path else MODEL
            fault = self.headers.get("X-Fixture-Fault")
            if fault == "unauthorized":
                return self.json({"error": "unauthorized"}, 401)
            if fault == "redirect":
                return self.respond(307, b"", {"Location": "/redirected"})
            if fault == "slow":
                STATS["slow"] += 1
                time.sleep(2)
            headers = {
                "Content-Type": "application/vnd.apple.coreml-model",
                "X-Mono-Model-SHA256": "0" * 64 if fault == "hash" else MODEL["sha256"],
                "X-Mono-Model-Version": descriptor["version"],
                "X-Mono-Feature-Schema": 7,
                "X-Mono-Target-Schema": 3 if fault == "schema" else 4,
            }
            return self.respond(200, PAYLOAD + b"extra" if fault == "size" else PAYLOAD, headers)
        self.json({"error": "missing"}, 404)

    def do_PUT(self):
        if self.headers.get("X-Admin-Token") != "fixture-admin":
            return self.json({"error": "unauthorized"}, 401)
        value = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert self.path.endswith("/api/ai/config")
        selected = value["resonance"]
        assert selected["modelID"] in (MODEL["id"], SECOND["id"])
        CONFIG.update(value["configuration"])
        CONFIG.update(enabled=value["enabled"], revision="fixture-published")
        CONFIG["resonance"] = dict(enabled=selected["enabled"], model=SECOND if selected["modelID"] == SECOND["id"] else MODEL)
        self.json(CONFIG)


STUBS = r'''
import Foundation
@MainActor enum FixtureDefaults {
    static let name = "mono.resonance.fixture." + UUID().uuidString
    static let value = UserDefaults(suiteName: name)!
    static func clear() { value.removePersistentDomain(forName: name) }
}
@MainActor enum KeychainHelper {
    static var storage: [String: Data] = [:]
    static func loadData(key: String) -> Data? { storage[key] }
    static func loadString(key: String) -> String? { storage[key].flatMap { String(data: $0, encoding: .utf8) } }
    @discardableResult static func save(key: String, data: Data) -> Bool { storage[key] = data; return true }
    @discardableResult static func save(key: String, value: String) -> Bool { save(key: key, data: Data(value.utf8)) }
    static func delete(key: String) { storage[key] = nil }
}
enum SecureConfig {
    enum Server { case primary }
    static let apiToken: String? = "fixture-user"
    static func apiBaseURL(for server: Server) -> String { CommandLine.arguments[1] + "/base" }
}
enum DeviceIdentifier { static let uuid = "fixture-device" }
final class FixtureAccess: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    var value: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue } }
    }
}
enum AppConfig {
    enum DeveloperAccess {
        private static let access = FixtureAccess()
        static var hasFullTools: Bool { get { access.value } set { access.value = newValue } }
    }
}
@MainActor final class OnlineAccessManager {
    static let shared = OnlineAccessManager()
    var canUseOnlineFeatures = true
}
enum AppLogger {
    enum Category { case localModel }
    static func info(_ message: String, step: String = "") {}
    static func warning(_ message: String, step: String = "", category: Category = .localModel, event: String = "") {}
}
enum AudioTrainingAdminError: Error { case fullAccessRequired }
enum AIEqualizerError: Error { case missingAPIKey, modelUnavailable }
enum AIEqualizerAnalysisTrigger { case manual, automatic }
struct AIProviderClient: Sendable {
    func fetchModels(configuration: AIProviderConfiguration, apiKey: String) async throws -> [String] { ["fixture-discovered"] }
}
'''


def extract(source, declaration):
    start = source.index(declaration)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        with tempfile.TemporaryDirectory(prefix="mono-resonance-client-") as temporary:
            folder = Path(temporary)
            # Reuse the production declarations, without importing the unrelated audio SDK.
            source = (ROOT / "Sources/Mono/Models/AI/AIEqualizerModels.swift").read_text()
            models = source[:source.index("struct AIUsageSnapshot")].replace("import FFmpegSwiftSDK\n", "")
            (folder / "ProviderModels.swift").write_text(models)
            (folder / "FixtureDependencies.swift").write_text(STUBS)
            # Isolate only persistence; all configuration and network logic remains production code.
            store = (ROOT / "Sources/Mono/Managers/AI/AIProviderConfigurationStore.swift").read_text()
            (folder / "ConfigurationStore.swift").write_text(store.replace("UserDefaults.standard", "FixtureDefaults.value"))
            tuning = (ROOT / "Sources/Mono/Managers/AI/AITuningServiceStore.swift").read_text()
            (folder / "TuningStore.swift").write_text(tuning.replace("UserDefaults = .standard", "UserDefaults = FixtureDefaults.value"))
            updates = (ROOT / "Sources/Mono/Managers/AI/AIResonanceUpdateStore.swift").read_text()
            updates = updates.replace("static let shared = AIResonanceUpdateStore()", "static let shared = AIResonanceUpdateStore(defaults: FixtureDefaults.value, bundledModel: FixtureBundle.model, bundledURL: FixtureBundle.url)")
            (folder / "UpdateStore.swift").write_text(updates)
            (folder / "bundled.bytes").write_bytes(PAYLOAD)
            (folder / "FixtureBundle.swift").write_text("import Foundation\n@MainActor enum FixtureBundle { static let model = try! JSONDecoder().decode(AudioTrainingModelInstallDescriptor.self, from: Data(#\"" + json.dumps(MODEL) + "\"#.utf8)); static var url: URL { URL(fileURLWithPath: CommandLine.arguments[2]) } }\n")
            runtime = (ROOT / "Sources/Mono/Managers/AI/AudioTrainingOnDeviceModelStore.swift").read_text()
            fixture = (ROOT / "Scripts/Tests/resonance_distribution_fixture.swift").read_text()
            methods = "\n".join(extract(runtime, declaration) for declaration in [
                "func clearDistributedAuthorization(", "func prepareDistributedModel(",
                "private func matches(", "private func canUse(", "func activeIdentity("
            ])
            fixture = fixture.replace("// PREPARATION_METHODS", methods)
            fixture = fixture.replace("// PREPARATION_STATE", "\n".join(
                line.strip() for line in runtime.splitlines()
                if line.strip().startswith(("private var distributedModel:", "private var distributionPreparation:"))
            ))
            analysis = (ROOT / "Sources/Mono/Managers/AI/AIEqualizerAgent+Analysis.swift").read_text()
            setup = analysis[analysis.index("        let onDeviceModelIdentity: String?"):analysis.index("        let configuration = requestContext.configuration")]
            fixture = fixture.replace("// PROVIDER_SELECTION", setup)
            result = analysis.index("            let output = generation.output")
            result_gate = analysis.rindex("            try Task.checkCancellation()", 0, result)
            fixture = fixture.replace("// GENERATION_RESULT_GATE", analysis[result_gate:result])
            run_start = analysis.index("    func runAnalysis(")
            gate = analysis[analysis.index("        guard tuningServiceStore.settings.isEnabled", run_start):analysis.index("        guard let song =", run_start)]
            fixture = fixture.replace("// SERVICE_ENABLED_GATE", gate)
            context = (ROOT / "Sources/Mono/Managers/AI/AIEqualizerAgent+ProviderContext.swift").read_text()
            fixture = fixture.replace("// PROVIDER_CONTEXT", "\n".join(extract(context, method) for method in [
                "func resolvedProviderRequestContext(", "func providerModelCacheKey("
            ]))
            controls = (ROOT / "Sources/Mono/Managers/AI/AIEqualizerAgent+Controls.swift").read_text()
            fixture = fixture.replace("// CONTROL_METHODS", "\n".join(extract(controls, method) for method in [
                "func handleTuningServiceChanged(", "func cancelAnalysis("
            ]))
            agent = (ROOT / "Sources/Mono/Managers/AI/AIEqualizerAgent.swift").read_text()
            fixture = fixture.replace("// SERVICE_SUBSCRIPTIONS", agent[agent.index("        tuningServiceStore.changes"):agent.index("        let player = PlayerManager.shared")])
            apply = (ROOT / "Sources/Mono/Managers/AI/AIEqualizerAgent+Application.swift").read_text()
            fixture = fixture.replace("// APPLY_ENABLED_GATE", apply[apply.index("        guard tuningServiceStore.settings.isEnabled"):apply.index("        let currentSong =")])
            (folder / "PreparationFixture.swift").write_text(fixture)
            training = (ROOT / "Sources/Mono/Models/AI/AudioTrainingModels.swift").read_text()
            (folder / "InstalledModel.swift").write_text("import Foundation\n" + "\n".join(
                extract(training, declaration) for declaration in [
                    "struct AudioTrainingInstalledModelStatus:", "enum AudioTrainingComputeMode:",
                    "struct AudioTrainingOnDeviceSettings:"
                ]
            ))
            executable = folder / "resonance-regressions"
            files = [
                folder / "ProviderModels.swift", folder / "FixtureDependencies.swift", folder / "ConfigurationStore.swift",
                folder / "TuningStore.swift", folder / "UpdateStore.swift", folder / "FixtureBundle.swift",
                ROOT / "Sources/Mono/Models/AI/AIResonanceDistribution.swift",
                ROOT / "Sources/Mono/Managers/AI/AIPersonalProviderStore.swift",
                ROOT / "Sources/Mono/Network/AI/AudioTrainingModelDownloader.swift",
                ROOT / "Sources/Mono/Models/AI/AudioTrainingProposalSummary.swift",
                folder / "InstalledModel.swift", folder / "PreparationFixture.swift",
            ]
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", *map(str, files), "-o", str(executable)], check=True, timeout=300)
            subprocess.run([str(executable), f"http://127.0.0.1:{server.server_port}", str(folder / "bundled.bytes")], check=True, timeout=60)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
