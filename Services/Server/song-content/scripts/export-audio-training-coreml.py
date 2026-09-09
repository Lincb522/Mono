#!/usr/bin/env python3
"""Export supported training snapshots as executable Core ML models."""

import argparse
import json
from pathlib import Path

import numpy as np
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder
from coremltools.models.utils import save_spec


def finite_vector(value, width, name):
    if not isinstance(value, list) or len(value) != width:
        raise ValueError(f"{name} must contain exactly {width} values")
    vector = np.asarray(value, dtype=np.float32)
    if vector.shape != (width,) or not np.isfinite(vector).all():
        raise ValueError(f"{name} contains an invalid value")
    return vector


def finite_matrix(value, rows, columns, name):
    if not isinstance(value, list) or len(value) != rows:
        raise ValueError(f"{name} must contain exactly {rows} rows")
    matrix = np.asarray(value, dtype=np.float32)
    if matrix.shape != (rows, columns) or not np.isfinite(matrix).all():
        raise ValueError(f"{name} has an invalid shape or value")
    return matrix


def metadata_count(metrics, first, second):
    return int(metrics.get(first, 0) or 0) + int(metrics.get(second, 0) or 0)


def export_model(source_path, output_path):
    source = json.loads(Path(source_path).read_text(encoding="utf-8"))
    artifact = source.get("artifact")
    if not isinstance(artifact, dict) or artifact.get("architecture") not in {
        "tiny-mlp-regression", "residual-conditional-mlp"
    }:
        raise ValueError("unsupported training artifact architecture")
    residual_model = artifact["architecture"] == "residual-conditional-mlp"
    if artifact.get("hiddenActivation") != "tanh":
        raise ValueError("hiddenActivation must be tanh")

    feature_names = artifact.get("featureNames")
    target_names = artifact.get("targetNames")
    if not isinstance(feature_names, list) or not feature_names:
        raise ValueError("featureNames is missing")
    if not isinstance(target_names, list) or not target_names:
        raise ValueError("targetNames is missing")
    if len(set(feature_names)) != len(feature_names) or len(set(target_names)) != len(target_names):
        raise ValueError("feature and target names must be unique")

    input_width = len(feature_names)
    output_width = len(target_names)
    hidden_bias = artifact.get("hiddenBias")
    if not isinstance(hidden_bias, list) or not hidden_bias:
        raise ValueError("hiddenBias is missing")
    hidden_width = len(hidden_bias)

    input_normalization = artifact.get("inputNormalization") or {}
    output_normalization = artifact.get("outputNormalization") or {}
    input_mean = finite_vector(input_normalization.get("mean"), input_width, "input mean")
    input_std = finite_vector(
        input_normalization.get("standardDeviation"), input_width, "input standard deviation"
    )
    output_mean = finite_vector(output_normalization.get("mean"), output_width, "output mean")
    output_std = finite_vector(
        output_normalization.get("standardDeviation"), output_width, "output standard deviation"
    )
    if np.any(input_std <= 0) or np.any(output_std <= 0):
        raise ValueError("normalization standard deviations must be positive")

    hidden_weights = finite_matrix(
        artifact.get("hiddenWeights"), hidden_width, input_width, "hiddenWeights"
    )
    hidden_bias_vector = finite_vector(hidden_bias, hidden_width, "hiddenBias")
    builder = NeuralNetworkBuilder(
        [("features", datatypes.Array(input_width))],
        [("tuning", datatypes.Array(output_width))],
        disable_rank5_shape_mapping=True,
        use_float_arraytype=True,
    )
    if residual_model:
        # Rank-aware broadcasting avoids both Scale's rank-3 requirement and
        # storing a quadratic diagonal matrix for an elementwise operation.
        builder.add_load_constant_nd(name="input_inverse_std", output_name="input_inverse_std",
                                     constant_value=(1.0 / input_std), shape=[input_width])
        builder.add_load_constant_nd(name="input_offset", output_name="input_offset",
                                     constant_value=(-input_mean / input_std), shape=[input_width])
        builder.add_multiply_broadcastable(name="scale_features", input_names=["features", "input_inverse_std"],
                                          output_name="scaled_features")
        builder.add_add_broadcastable(name="normalize_features", input_names=["scaled_features", "input_offset"],
                                     output_name="normalized_features")
    else:
        builder.add_inner_product(
            name="normalize_features", W=np.diag(1.0 / input_std).astype(np.float32), b=(-input_mean / input_std),
            input_channels=input_width, output_channels=input_width, has_bias=True,
            input_name="features", output_name="normalized_features",
        )
    builder.add_clip(
        name="clip_normalized_features",
        input_name="normalized_features",
        output_name="clipped_features",
        min_value=-8.0,
        max_value=8.0,
    )
    builder.add_inner_product(
        name="hidden_dense",
        W=hidden_weights,
        b=hidden_bias_vector,
        input_channels=input_width,
        output_channels=hidden_width,
        has_bias=True,
        input_name="clipped_features",
        output_name="hidden_linear",
    )
    builder.add_activation(
        name="hidden_tanh",
        non_linearity="TANH",
        input_name="hidden_linear",
        output_name="hidden",
    )
    output_input = "hidden"
    output_input_width = hidden_width
    if residual_model:
        if artifact.get("intentActivation") != "tanh":
            raise ValueError("intentActivation must be tanh")
        residual_scale = float(artifact.get("residualScale", 0))
        if not np.isfinite(residual_scale) or abs(residual_scale - 2 ** -0.5) > 1e-8:
            raise ValueError("residualScale must be 1/sqrt(2)")
        builder.add_inner_product(
            name="residual_dense",
            W=finite_matrix(artifact.get("residualWeights"), hidden_width, hidden_width, "residualWeights"),
            b=finite_vector(artifact.get("residualBias"), hidden_width, "residualBias"),
            input_channels=hidden_width, output_channels=hidden_width, has_bias=True,
            input_name="hidden", output_name="residual_linear",
        )
        builder.add_activation(name="residual_tanh", non_linearity="TANH",
                               input_name="residual_linear", output_name="residual")
        builder.add_add_broadcastable(name="residual_add", input_names=["hidden", "residual"],
                                     output_name="residual_sum")
        builder.add_activation(name="residual_scale", non_linearity="LINEAR", params=[residual_scale, 0],
                               input_name="residual_sum", output_name="residual_hidden")
        output_input = "residual_hidden"
        intent_bias = artifact.get("intentBias")
        if intent_bias is not None:
            if not isinstance(intent_bias, list) or not intent_bias:
                raise ValueError("intentBias must be nonempty when enabled")
            output_input_width = len(intent_bias)
            builder.add_inner_product(
                name="intent_dense",
                W=finite_matrix(artifact.get("intentWeights"), output_input_width, hidden_width, "intentWeights"),
                b=finite_vector(intent_bias, output_input_width, "intentBias"),
                input_channels=hidden_width, output_channels=output_input_width, has_bias=True,
                input_name="residual_hidden", output_name="intent_linear",
            )
            builder.add_activation(name="intent_tanh", non_linearity="TANH",
                                   input_name="intent_linear", output_name="intent")
            output_input = "intent"
            builder.add_inner_product(
                name="output_skip",
                W=finite_matrix(artifact.get("outputSkipWeights"), output_width, hidden_width, "outputSkipWeights") * output_std[:, np.newaxis],
                b=np.zeros(output_width, dtype=np.float32),
                input_channels=hidden_width, output_channels=output_width, has_bias=True,
                input_name="residual_hidden", output_name="skip_output",
            )
        elif artifact.get("intentWeights") is not None or artifact.get("outputSkipWeights") is not None:
            raise ValueError("disabled intent must not have intent or skip weights")
        output_weights = finite_matrix(artifact.get("outputHeadWeights"), output_width, output_input_width, "outputHeadWeights")
        output_bias = finite_vector(artifact.get("outputHeadBias"), output_width, "outputHeadBias")
    else:
        output_weights = finite_matrix(artifact.get("outputWeights"), output_width, hidden_width, "outputWeights")
        output_bias = finite_vector(artifact.get("outputBias"), output_width, "outputBias")

    # Denormalization is affine; the nonlinear intent path itself cannot fold.
    denormalized_output_weights = output_weights * output_std[:, np.newaxis]
    denormalized_output_bias = output_bias * output_std + output_mean
    builder.add_inner_product(
        name="output_dense",
        W=denormalized_output_weights,
        b=denormalized_output_bias,
        input_channels=output_input_width,
        output_channels=output_width,
        has_bias=True,
        input_name=output_input,
        output_name="head_output" if output_input == "intent" else "tuning",
    )
    if output_input == "intent":
        builder.add_add_broadcastable(name="output_add", input_names=["head_output", "skip_output"],
                                     output_name="tuning")

    spec = builder.spec
    metadata = spec.description.metadata
    model_family = str(artifact.get("modelFamily") or "Mono Resonance")
    model_name = str(artifact.get("modelName") or "Mono Resonance S1")
    metadata.shortDescription = f"{model_name} tuning model"
    metadata.author = "Mono"
    metadata.license = "Private"
    metrics = source.get("metrics") if isinstance(source.get("metrics"), dict) else {}
    user_defined = {
        "mono.model_id": str(source.get("id", "")),
        "mono.model_version": str(source.get("version", "")),
        "mono.model_family": model_family,
        "mono.model_name": model_name,
        "mono.architecture": artifact["architecture"],
        "mono.feature_schema_version": str(artifact.get("featureSchemaVersion", "")),
        "mono.target_schema_version": str(artifact.get("targetSchemaVersion", "")),
        "mono.graphic_eq_modes": json.dumps(
            artifact.get("graphicEQModes", []), separators=(",", ":")
        ),
        "mono.training_strategy": str(artifact.get("trainingStrategy", "")),
        "mono.confidence_calibration": json.dumps(
            artifact.get("confidenceCalibration"), separators=(",", ":"), allow_nan=False
        ),
        "mono.feature_names": json.dumps(feature_names, separators=(",", ":")),
        "mono.target_names": json.dumps(target_names, separators=(",", ":")),
        "mono.complete_sample_count": str(
            metadata_count(metrics, "completeTrainingSamples", "completeValidationSamples")
        ),
        "mono.style_conditioned_sample_count": str(
            metadata_count(
                metrics,
                "styleConditionedTrainingSamples",
                "styleConditionedValidationSamples",
            )
        ),
        "mono.temporally_conditioned_sample_count": str(
            metadata_count(
                metrics,
                "temporallyConditionedTrainingSamples",
                "temporallyConditionedValidationSamples",
            )
        ),
        "mono.learning_conditioned_sample_count": str(
            metadata_count(
                metrics,
                "learningConditionedTrainingSamples",
                "learningConditionedValidationSamples",
            )
        ),
        "mono.device_conditioned_sample_count": str(
            metadata_count(
                metrics,
                "deviceConditionedTrainingSamples",
                "deviceConditionedValidationSamples",
            )
        ),
        "mono.distinct_track_count": str(
            metadata_count(metrics, "distinctTrainingTracks", "distinctValidationTracks")
        ),
        "mono.legacy_sample_count": str(
            metadata_count(metrics, "legacyTrainingSamples", "legacyValidationSamples")
        ),
        "mono.legacy_prior_weight": str(metrics.get("legacyPriorWeight", 0) or 0),
        "mono.complete_account_count": str(int(metrics.get("completeAccountCount", 0) or 0)),
        "mono.target_mode": str(artifact.get("targetMode") or metrics.get("targetMode") or "population"),
        "mono.quality_warnings": json.dumps(
            list(metrics.get("qualityWarnings") or []), separators=(",", ":")
        ),
        # The raw-unit input mean lets the device reconstruct the population
        # prior input (mean + branch/profile/intensity one-hots) and blend the
        # track-specific correction in proportion to branch coverage.
        "mono.input_mean": json.dumps(
            [round(float(value), 6) for value in input_mean.tolist()], separators=(",", ":")
        ),
    }
    for key, value in user_defined.items():
        metadata.userDefined[key] = value

    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    save_spec(spec, str(output))
    if not output.is_file() or output.stat().st_size < 256:
        raise ValueError("Core ML exporter produced an invalid model file")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    export_model(args.source, args.output)


if __name__ == "__main__":
    main()
