"""Executable export parity: Node trainer -> Core ML -> native macOS runtime."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent
SERVICE = SCRIPTS.parent


class ExportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("exporter", SCRIPTS / "export-audio-training-coreml.py")
        cls.exporter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.exporter)

    def test_residual_models_match_trainer_including_clipped_inputs(self):
        for intent_units in [0, 3]:
            with self.subTest(intent_units=intent_units), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                script = """
const t = require('./audio-tuning-training');
const examples = Array.from({length: 12}, (_, i) => ({
  id: String(i), trackGroup: String(i), accountId: String(i % 3),
  graphicEQMode: i % 2 ? 'tenBand' : 'thirtyTwoBand', tuningProfile: 'standard',
  x: t.featureNames.map((_, j) => Math.sin(i + j) * .2),
  y: t.targetNames.map((_, j) => Math.cos(i + j) * .3),
  targetMask: t.targetNames.map(() => 1), sampleWeight: 1
}));
const calibration = Array.from({length: 160}, (_, i) => ({...examples[i % examples.length],
  id: `held-${i}`, trackGroup: `held-${i}`}));
const artifact = t.trainTinyModelSync({training: examples, validation: [], calibration,
  settings: t.normalizeSettings({epochs: 2, hiddenUnits: 4, intentUnits: INTENT, earlyStoppingPatience: 0})});
Object.assign(artifact, {featureNames: t.featureNames, targetNames: t.targetNames,
  hiddenActivation: 'tanh', modelName: t.MODEL_NAME, modelFamily: t.MODEL_FAMILY,
  graphicEQModes: ['tenBand', 'thirtyTwoBand'], bandCounts: [10, 32],
  featureSchemaVersion: t.FEATURE_SCHEMA_VERSION, targetSchemaVersion: t.TARGET_SCHEMA_VERSION});
const cases = [-100, -.2, 0, .2, 100].map(value => {
  const input = t.featureNames.map((_, j) => value * Math.sin(j));
  const normalized = input.map((v, j) => Math.min(8, Math.max(-8,
    (v - artifact.inputNormalization.mean[j]) / artifact.inputNormalization.standardDeviation[j])));
  const expected = t.forward(artifact, normalized).prediction.map((v, j) =>
    v * artifact.outputNormalization.standardDeviation[j] + artifact.outputNormalization.mean[j]);
  return {input, expected};
});
console.log(JSON.stringify({source: {artifact, version: t.MODEL_VERSION_PREFIX + '-20260906000000-test0001',
  featureSchemaVersion: t.FEATURE_SCHEMA_VERSION, targetSchemaVersion: t.TARGET_SCHEMA_VERSION}, cases}));
""".replace("INTENT", str(intent_units))
                data = json.loads(subprocess.run(["node", "-e", script], cwd=SERVICE,
                                                check=True, capture_output=True, text=True, timeout=30).stdout)
                source = root / "source.json"
                source.write_text(json.dumps(data["source"]), encoding="utf-8")
                output = root / "model.mlmodel"
                self.exporter.export_model(source, output)
                cases = root / "cases.json"
                cases.write_text(json.dumps(data["cases"]), encoding="utf-8")
                from coremltools.models.utils import load_spec
                metadata = load_spec(str(output)).description.metadata.userDefined
                calibration = json.loads(metadata["mono.confidence_calibration"])
                self.assertEqual(calibration, data["source"]["artifact"]["confidenceCalibration"])
                self.assertEqual(calibration["branches"]["thirtyTwoBand:standard"]["status"], "calibrated")
                self.assertEqual(calibration["branches"]["tenBand:monoSpatialEnhancement"]["radiusDB"], None)
                self.assertGreater(output.stat().st_size, 256)
                self.assertLess(output.stat().st_size, 500_000, "normalization must not store a quadratic diagonal matrix")
                if sys.platform != "darwin":
                    self.skipTest("Native Core ML prediction requires macOS")
                calibration_file = root / "calibration.json"
                calibration_file.write_text(json.dumps(calibration), encoding="utf-8")
                outputs = [output]
                if public_repository := os.environ.get("MONO_RESONANCE_REPOSITORY"):
                    public = Path(public_repository)
                    sys.path.insert(0, str(public / "src"))
                    from mono_resonance.inference import predict
                    from mono_resonance.validation import validate_model_document
                    from mono_resonance.schema import feature_names_v7, target_names_v4
                    self.assertEqual(list(feature_names_v7()), data["source"]["artifact"]["featureNames"])
                    self.assertEqual(list(target_names_v4()), data["source"]["artifact"]["targetNames"])
                    report = validate_model_document(data["source"])
                    self.assertTrue(report.is_valid, report.errors)
                    for case in data["cases"]:
                        actual = predict(data["source"], case["input"]).vector
                        self.assertLess(max(abs(a - b) for a, b in zip(actual, case["expected"])), 1e-10)
                    spec = importlib.util.spec_from_file_location("public_exporter", public / "tools/export_coreml.py")
                    exporter = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(exporter)
                    public_output = root / "public-model.mlmodel"
                    exporter.export_model(source, public_output)
                    outputs.append(public_output)
                for model in outputs:
                    result = subprocess.run(["swift", str(SCRIPTS / "verify-audio-training-coreml.swift"),
                                             str(model), str(cases), *([str(calibration_file)] if model == output else [])], capture_output=True,
                                            text=True, timeout=120)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    print(model.name + ": " + result.stdout.strip())


if __name__ == "__main__":
    unittest.main()
