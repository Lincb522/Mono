const crypto = require('node:crypto')
const { spawn } = require('node:child_process')
const fs = require('node:fs')
const path = require('node:path')
const { Worker, isMainThread, parentPort, workerData } = require('node:worker_threads')
const { isSelfGeneratedProposal, manualGainDelta, hasHumanCorrection } = require('./audio-training-samples')
const { RELEASE_NOTES_VERSION, generateReleaseNotes } = require('./audio-training-release-notes')

const ACTIVE_STATES = new Set(['queued', 'collecting', 'training', 'validating'])
const FEATURE_SCHEMA_VERSION = 7
const TARGET_SCHEMA_VERSION = 4
const MODEL_FAMILY = 'Mono Resonance'
const MODEL_NAME = 'Mono Resonance S2'
const MODEL_VERSION_PREFIX = `mono-resonance-s2-schema${FEATURE_SCHEMA_VERSION}`
const MODEL_ARCHITECTURE = 'residual-conditional-mlp'
const CORE_ML_ARTIFACT_FORMAT = 'coreml-neuralnetwork-v2'
const TRACK_SECTION_COUNT = 3
const TRACK_BAND_COUNT = 10
const DEVICE_CURVE_BAND_COUNT = 32
const DEVICE_FILTER_SLOT_COUNT = 12
const SUPPORTED_SAMPLE_SCHEMA_VERSIONS = new Set([1, 2, 3, 4])
const TARGET_MODES = new Set(['population', 'personalized', 'joint'])
const MINIMUM_NORMALIZATION_SAMPLES = 8
const MINIMUM_SELECTION_VALIDATION_SAMPLES = 16
const MINIMUM_CALIBRATION_TRACKS = 32
const CALIBRATION_COVERAGE = 0.9
const CALIBRATION_METHOD = 'split-conformal-track-max-v1'
const CALIBRATION_NUMERICAL_MARGIN_DB = 0.001
const MANUAL_GAIN_DELTA_LIMIT_DB = 12
const GRADIENT_CLIP_NORM = 5
const MOMENTUM = 0.9
const ALL_TRAINING_BRANCHES = [
  'tenBand:standard',
  'tenBand:monoSpatialEnhancement',
  'thirtyTwoBand:standard',
  'thirtyTwoBand:monoSpatialEnhancement'
]

const REQUIRED_TRAINING_BRANCHES = ALL_TRAINING_BRANCHES.filter(branch => branch.startsWith('tenBand:'))

const genreFeatureValues = [
  'electronic', 'hiphop', 'rock', 'acoustic', 'ballad', 'pop'
]

const instrumentFeatureValues = [
  'drums', 'bass', 'vocals', 'synth', 'guitar', 'piano', 'strings'
]

const outputKindFeatureValues = [
  'builtInSpeaker', 'wired', 'bluetooth', 'car', 'airPlay', 'usb', 'other'
]

const tuningIntensityFeatureValues = ['smart', 'gentle', 'standard', 'strong']
const tuningProfileFeatureValues = ['standard', 'monoSpatialEnhancement']
const deviceProfileSourceFeatureValues = [
  'none', 'routeDefault', 'airPods', 'opra', 'custom', 'profile', 'mixed'
]
const deviceFilterKindFeatureValues = [
  'peak_dip', 'low_shelf', 'high_shelf', 'low_pass',
  'high_pass', 'band_pass', 'band_stop'
]

const scalarFeatureNames = [
  'sampleDuration', 'sampleRate', 'frameCount', 'spectralCentroidHz',
  'spectralRolloffHz', 'rmsDBFS', 'dynamicSpreadDB', 'integratedLUFS',
  'shortTermLUFS', 'momentaryLUFS', 'loudnessRangeLU', 'samplePeakDBFS',
  'estimatedTruePeakDBTP', 'crestFactorDB', 'dynamicRangeDR', 'clippingRatio',
  'phaseCorrelation', 'monoCompatibility', 'measuredStereoWidth',
  'spectralFlatness', 'spectralBandwidthHz', 'spectralFlux', 'lowEnergyRatio',
  'midEnergyRatio', 'highEnergyRatio', 'estimatedBPM', 'tempoConfidence',
  'tempoStability', 'keyConfidence', 'dominantPitchHz', 'melodyRangeSemitones',
  'melodicActivity', 'transientDensity', 'currentBassGain', 'currentTrebleGain',
  'currentSurroundLevel', 'currentReverbLevel', 'currentStereoWidth',
  'professionalProcessingIntensity'
]

const booleanFeatureNames = [
  'outputCalibrationEnabled', 'loudnessMatchingEnabled',
  'smartSongCompensationEnabled', 'dynamicEQEnabled',
  'multibandDynamicsEnabled', 'parametricEQEnabled'
]

const enhanceTargetNames = [
  'transientAttack', 'transientSustain', 'vocalFocus', 'airAmount',
  'deEssAmount', 'lowFrequencyFocus', 'stageWidth', 'microDynamics',
  'lowLevelCompensation'
]

const effectTargetNames = [
  'targetLUFS', 'targetLRA', 'truePeakCeilingDB', 'compressorThresholdDB',
  'compressorRatio', 'compressorAttackMS', 'compressorReleaseMS',
  'compressorMakeupDB', 'subboostGainDB', 'subboostCutoffHz',
  'crossfeedStrength', 'haasDelayMS', 'virtualBassCutoffHz',
  'virtualBassStrength', 'exciterAmountDB', 'exciterFrequencyHz',
  'finalLimiterCeilingDB'
]

const effectBooleanTargetNames = [
  'loudnessNormalizationEnabled', 'compressorEnabled', 'subboostEnabled',
  'bs2bEnabled', 'crossfeedEnabled', 'haasEnabled', 'virtualBassEnabled',
  'exciterEnabled', 'softclipEnabled', 'finalLimiterEnabled'
]

const dynamicBandFields = ['frequency', 'q', 'thresholdDB', 'ratio', 'maxReductionDB', 'attackMS', 'releaseMS']
const parametricTypes = ['peak', 'lowShelf', 'highShelf', 'lowPass', 'highPass', 'notch']
const professionalTargetNames = [
  ...Array.from({ length: 4 }, (_, slot) => [
    `professional.dynamicEQ.bands.${slot}.active`,
    ...dynamicBandFields.map((field) => `professional.dynamicEQ.bands.${slot}.${field}`)
  ]).flat(),
  ...Array.from({ length: 6 }, (_, slot) => [
    `professional.parametricEQ.bands.${slot}.active`,
    ...parametricTypes.map((type) => `professional.parametricEQ.bands.${slot}.type.${type}`),
    ...['frequency', 'gainDB', 'q'].map((field) => `professional.parametricEQ.bands.${slot}.${field}`)
  ]).flat(),
  ...['lowCrossoverHz', 'highCrossoverHz', 'attackMS', 'releaseMS'].map((field) => `professional.multiband.${field}`),
  ...['thresholdsDB', 'ratios', 'maxReductionDB'].flatMap((field) =>
    Array.from({ length: 3 }, (_, slot) => `professional.multiband.${field}.${slot}`))
]

function bandCountForMode(mode) {
  return mode === 'thirtyTwoBand' ? 32 : 10
}

function bandBranchNames(name) {
  return [
    ...Array.from({ length: 10 }, (_, index) => `tenBand.${name}.${index}`),
    ...Array.from({ length: 32 }, (_, index) => `thirtyTwoBand.${name}.${index}`)
  ]
}

const legacyFeatureNames = [
  ...bandBranchNames('bandEnergyDB'),
  ...scalarFeatureNames,
  ...Array.from({ length: 12 }, (_, index) => `chroma.${index}`),
  'vocalReference.confidence', 'vocalReference.presence', 'vocalReference.warmth',
  'vocalReference.brightness', 'vocalReference.airiness',
  'vocalReference.dynamicExpression',
  ...booleanFeatureNames,
  ...bandBranchNames('deviceReferenceGainsDB'),
  'graphicEQMode.thirtyTwoBand'
]

const routeAndIntentFeatureNames = [
  ...outputKindFeatureValues.map((name) => `outputKind.${name}`),
  ...tuningIntensityFeatureValues.map((name) => `tuningIntensity.${name}`),
  ...tuningProfileFeatureValues.map((name) => `tuningProfile.${name}`)
]

const styleConditionedFeatureNamesV2 = [
  ...genreFeatureValues.map((name) => `genreHint.${name}`),
  ...instrumentFeatureValues.map((name) => `instrumentHint.${name}`),
  ...routeAndIntentFeatureNames
]

const temporalTrackFeatureNames = [
  ...bandBranchNames('bandEnergySpreadDB'),
  ...['tenBand', 'thirtyTwoBand'].flatMap((mode) => {
    const bandCount = bandCountForMode(mode)
    return Array.from(
      { length: TRACK_SECTION_COUNT * bandCount },
      (_, index) => `${mode}.sectionBandEnergyDB.${Math.floor(index / bandCount)}.${index % bandCount}`
    )
  }),
  'spectralCentroidP10Hz', 'spectralCentroidP90Hz',
  'spectralRolloffP10Hz', 'spectralRolloffP90Hz',
  'spectralFluxP90', 'rmsP10DBFS', 'rmsP50DBFS', 'rmsP90DBFS'
]

const learningConditionedFeatureNames = [
  'learning.active', 'learning.confidence', 'learning.evidenceCount',
  ...bandBranchNames('learning.bandAdjustments'),
  'learning.bassAdjustment', 'learning.trebleAdjustment',
  'learning.surroundAdjustment', 'learning.reverbAdjustment',
  'learning.stereoWidthAdjustment', 'learning.processingIntensityAdjustment'
]

const detailedDeviceFeatureNames = [
  'device.detailActive', 'device.calibrationEnabled',
  'device.profileActive', 'device.profileIsCustom',
  'device.outputSampleRate', 'device.outputChannelCount',
  'device.outputLatencyMS', 'device.ioBufferDurationMS',
  'device.profilePreampDB', 'device.filterCount',
  ...deviceProfileSourceFeatureValues.map((name) => `device.profileSource.${name}`),
  ...Array.from(
    { length: TRACK_BAND_COUNT },
    (_, index) => `device.routeDefaultGainsDB.${index}`
  ),
  ...Array.from(
    { length: DEVICE_CURVE_BAND_COUNT },
    (_, index) => `device.profileGainsDB.${index}`
  ),
  ...Array.from(
    { length: DEVICE_CURVE_BAND_COUNT },
    (_, index) => `device.effectiveGainsDB.${index}`
  ),
  ...Array.from({ length: DEVICE_FILTER_SLOT_COUNT }, (_, slot) => [
    `device.filter.${slot}.active`,
    ...deviceFilterKindFeatureValues.map((kind) => `device.filter.${slot}.kind.${kind}`),
    `device.filter.${slot}.frequencyHz`, `device.filter.${slot}.gainDB`,
    `device.filter.${slot}.q`, `device.filter.${slot}.slopeDBPerOctave`
  ]).flat()
]

const featureNames = [
  ...legacyFeatureNames,
  ...genreFeatureValues.map((name) => `genreScore.${name}`),
  ...instrumentFeatureValues.map((name) => `instrumentScore.${name}`),
  ...routeAndIntentFeatureNames,
  ...temporalTrackFeatureNames,
  ...learningConditionedFeatureNames,
  ...detailedDeviceFeatureNames
]

const targetNames = [
  ...Array.from({ length: 10 }, (_, index) => `tenBand.gains.${index}`),
  ...Array.from({ length: 32 }, (_, index) => `thirtyTwoBand.gains.${index}`),
  'preampDB', 'tone.bassGain', 'tone.trebleGain',
  'spatial.surroundLevel', 'spatial.reverbLevel', 'spatial.stereoWidth',
  ...enhanceTargetNames.map((name) => `enhance.${name}`),
  'enhance.isEnabled',
  'calibration.outputCalibrationEnabled', 'calibration.loudnessMatchingEnabled',
  'calibration.smartSongCompensationEnabled',
  'professional.processingIntensity', 'professional.dynamicEQ.enabled',
  'professional.multiband.enabled', 'professional.parametricEQ.enabled',
  ...effectTargetNames.map((name) => `effects.${name}`),
  ...effectBooleanTargetNames.map((name) => `effects.${name}`),
  ...professionalTargetNames
]

function targetFamily(name) {
  if (/^(tenBand|thirtyTwoBand)\.gains\./.test(name)) return 'graphicEQ'
  if (name.startsWith('professional.')) return name.split('.').slice(0, 2).join('.')
  return name.split('.')[0]
}

// Equal family mass keeps detailed filter slots from overwhelming a native EQ
// curve. Preserve the total active-target mass and never supervise masked slots.
function targetLossWeights(mask) {
  const counts = new Map()
  mask.forEach((active, index) => {
    if (active) {
      const family = targetFamily(targetNames[index])
      counts.set(family, (counts.get(family) || 0) + 1)
    }
  })
  const mass = [...counts.values()].reduce((sum, value) => sum + value, 0) / Math.max(1, counts.size)
  return mask.map((active, index) => active ? mass / counts.get(targetFamily(targetNames[index])) : 0)
}

function createAudioTuningTrainingService({
  directory,
  cloudDatabasePath,
  trainingSampleDatabasePath,
  coreMLPythonPath = process.env.AUDIO_TRAINING_PYTHON || 'python3',
  coreMLExporterPath = path.join(__dirname, 'scripts', 'export-audio-training-coreml.py'),
  coreMLExporter,
  logger = console
}) {
  if (!directory) throw new TypeError('audio training directory is required')
  const { DatabaseSync } = require('node:sqlite')
  fs.mkdirSync(directory, { recursive: true })
  const modelsDirectory = path.join(directory, 'models')
  fs.mkdirSync(modelsDirectory, { recursive: true })
  const databasePath = path.join(directory, 'audio-training.sqlite')
  const resolvedCloudDatabasePath = cloudDatabasePath || path.join(path.dirname(directory), 'cloud-storage.sqlite')
  const resolvedSampleDatabasePath = trainingSampleDatabasePath
    || path.join(path.dirname(directory), 'training-samples.sqlite')
  const database = new DatabaseSync(databasePath)
  database.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;
    PRAGMA busy_timeout = 5000;
    CREATE TABLE IF NOT EXISTS audio_training_settings (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      epochs INTEGER NOT NULL,
      hidden_units INTEGER NOT NULL,
      learning_rate REAL NOT NULL,
      validation_percent INTEGER NOT NULL,
      minimum_samples INTEGER NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS audio_training_jobs (
      id TEXT PRIMARY KEY,
      state TEXT NOT NULL,
      progress REAL NOT NULL DEFAULT 0,
      epoch INTEGER NOT NULL DEFAULT 0,
      total_epochs INTEGER NOT NULL,
      sample_count INTEGER NOT NULL DEFAULT 0,
      training_count INTEGER NOT NULL DEFAULT 0,
      validation_count INTEGER NOT NULL DEFAULT 0,
      training_loss REAL,
      validation_loss REAL,
      dataset_fingerprint TEXT,
      settings_json TEXT NOT NULL,
      error_message TEXT,
      model_id TEXT,
      created_by TEXT,
      created_at TEXT NOT NULL,
      started_at TEXT,
      finished_at TEXT,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS audio_training_jobs_created_idx
      ON audio_training_jobs(created_at DESC);
    CREATE TABLE IF NOT EXISTS audio_training_models (
      id TEXT PRIMARY KEY,
      version TEXT NOT NULL UNIQUE,
      feature_schema_version INTEGER NOT NULL,
      target_schema_version INTEGER NOT NULL,
      artifact_json TEXT NOT NULL,
      metrics_json TEXT NOT NULL,
      dataset_fingerprint TEXT NOT NULL,
      sample_count INTEGER NOT NULL,
      created_by TEXT,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS audio_training_model_publication (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      model_id TEXT NOT NULL REFERENCES audio_training_models(id),
      published_by TEXT,
      published_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS audio_training_model_artifacts (
      model_id TEXT PRIMARY KEY REFERENCES audio_training_models(id) ON DELETE CASCADE,
      format TEXT NOT NULL,
      relative_path TEXT NOT NULL,
      sha256 TEXT NOT NULL,
      byte_count INTEGER NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS audio_training_published_models (
      model_id TEXT PRIMARY KEY REFERENCES audio_training_models(id),
      published_at TEXT NOT NULL
    );
    INSERT OR IGNORE INTO audio_training_published_models (model_id, published_at)
      SELECT model_id, published_at FROM audio_training_model_publication;
  `)
  const publicationColumns = new Set(database.prepare('PRAGMA table_info(audio_training_published_models)').all().map(row => row.name))
  for (const column of ['release_summary', 'release_notes']) {
    if (!publicationColumns.has(column)) database.exec(`ALTER TABLE audio_training_published_models ADD COLUMN ${column} TEXT NOT NULL DEFAULT ''`)
  }
  if (!publicationColumns.has('release_generator_version')) {
    database.exec('ALTER TABLE audio_training_published_models ADD COLUMN release_generator_version INTEGER NOT NULL DEFAULT 0')
  }
  migrateSettingsTable(database)
  migrateReleaseNotes(database)
  const defaults = normalizeSettings({})
  database.prepare(`INSERT OR IGNORE INTO audio_training_settings
    (singleton, epochs, hidden_units, learning_rate, validation_percent, minimum_samples,
     prior_weight, weight_decay, early_stopping_patience, intent_units, target_mode, updated_at)
    VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(defaults.epochs, defaults.hiddenUnits, defaults.learningRate,
      defaults.validationPercent, defaults.minimumSamples,
      defaults.priorWeight, defaults.weightDecay, defaults.earlyStoppingPatience,
      defaults.intentUnits, defaults.targetMode, new Date().toISOString())
  database.prepare(`UPDATE audio_training_jobs SET state = 'failed',
    error_message = '服务重启中断了训练，请重新启动。', finished_at = ?, updated_at = ?
    WHERE state IN ('queued', 'collecting', 'training', 'validating')`)
    .run(new Date().toISOString(), new Date().toISOString())

  const statements = prepareStatements(database)
  const exportModel = coreMLExporter || ((options) => exportCoreMLViaPython({
    ...options,
    pythonPath: coreMLPythonPath,
    exporterPath: coreMLExporterPath
  }))
  let activeRun = null
  let closed = false
  const artifactRuns = new Map()

  function settings() {
    return hydrateSettings(statements.selectSettings.get())
  }

  function updateSettings(patch) {
    if (activeRun) throw trainingError('TRAINING_ACTIVE', '训练进行中，不能修改设置。', 409)
    const value = normalizeSettings({ ...settings(), ...(patch || {}) })
    const now = new Date().toISOString()
    statements.updateSettings.run(
      value.epochs,
      value.hiddenUnits,
      value.learningRate,
      value.validationPercent,
      value.minimumSamples,
      value.priorWeight,
      value.weightDecay,
      value.earlyStoppingPatience,
      value.intentUnits,
      value.targetMode,
      now
    )
    return settings()
  }

  function inspectDataset({ includeVectors = false, targetMode } = {}) {
    const result = collectDataset(resolvedCloudDatabasePath, {
      includeVectors,
      targetMode: targetMode || settings().targetMode,
      trainingSampleDatabasePath: resolvedSampleDatabasePath
    })
    return includeVectors ? result : result.stats
  }

  function status() {
    return {
      settings: settings(),
      dataset: inspectDataset(),
      currentJob: hydrateJob(statements.selectLatestJob.get()),
      currentModel: hydrateStoredModel(statements.selectLatestModel.get()),
      publishedModel: hydrateStoredModel(statements.selectPublishedModel.get())
    }
  }

  function startTraining(actorId) {
    if (activeRun || statements.selectActiveJob.get()) {
      throw trainingError('TRAINING_ACTIVE', '已有训练任务正在运行。', 409)
    }
    const configuration = settings()
    const dataset = inspectDataset()
    if (dataset.trainableSamples < configuration.minimumSamples) {
      throw trainingError(
        'INSUFFICIENT_TRAINING_SAMPLES',
        `可训练样本不足：需要 ${configuration.minimumSamples}，当前 ${dataset.trainableSamples}。`,
        422
      )
    }
    assertRequiredTrainingBranches(dataset.branchSamples)
    const id = crypto.randomUUID()
    const now = new Date().toISOString()
    statements.insertJob.run(
      id,
      configuration.epochs,
      JSON.stringify(configuration),
      cleanActor(actorId),
      now,
      now
    )
    activeRun = { id, cancelled: false }
    setImmediate(() => runTraining(id, actorId).catch((error) => {
      logger.error('[audio-training] Training failed:', error)
    }))
    return hydrateJob(statements.selectJob.get(id))
  }

  function cancelTraining(jobId) {
    const job = hydrateJob(statements.selectJob.get(jobId))
    if (!job) throw trainingError('TRAINING_JOB_NOT_FOUND', '训练任务不存在。', 404)
    if (!ACTIVE_STATES.has(job.state)) return job
    if (activeRun?.id === jobId) activeRun.cancelled = true
    finishJob(jobId, 'cancelled', { errorMessage: null })
    return hydrateJob(statements.selectJob.get(jobId))
  }

  async function publishModel(modelId, actorId) {
    const model = statements.selectModel.get(modelId)
    if (!model) throw trainingError('TRAINING_MODEL_NOT_FOUND', '训练模型不存在。', 404)
    await ensureCoreMLArtifact(modelId)
    const now = new Date().toISOString()
    database.exec('BEGIN IMMEDIATE')
    try {
      const release = releaseNotesForModel(model)
      statements.publishModel.run(modelId, cleanActor(actorId), now)
      statements.recordPublication.run(modelId, now, release.summary, release.notes, RELEASE_NOTES_VERSION)
      database.exec('COMMIT')
    } catch (error) {
      database.exec('ROLLBACK')
      throw error
    }
    return hydrateStoredModel(statements.selectPublishedModel.get())
  }

  function publishedModels() {
    return statements.selectPublishedModels.all().flatMap((row) => {
      const artifact = statements.selectArtifact.get(row.id)
      if (row.feature_schema_version !== 7 || row.target_schema_version !== 4
        || !row.version.startsWith('mono-resonance-s2-')
        || artifact?.format !== CORE_ML_ARTIFACT_FORMAT) return []
      const metrics = parseJSON(row.metrics_json, {})
      const count = (value) => Math.max(0, Math.trunc(Number(value) || 0))
      const sum = (name) => count(metrics[`${name}TrainingSamples`]) + count(metrics[`${name}ValidationSamples`])
      const branchKeys = new Set([
        ...Object.keys(metrics.completeBranchTrainingSamples || {}),
        ...Object.keys(metrics.completeBranchValidationSamples || {})
      ])
      return [{
        id: row.id, version: row.version, createdAt: row.created_at,
        fileName: modelDownloadFileName(row.created_at, row.version), release: hydrateModelRelease(row),
        sha256: artifact.sha256, byteCount: artifact.byte_count,
        featureSchemaVersion: row.feature_schema_version, targetSchemaVersion: row.target_schema_version,
        completeSampleCount: sum('complete'), legacySampleCount: sum('legacy'),
        learningConditionedSampleCount: sum('learningConditioned'),
        deviceConditionedSampleCount: sum('deviceConditioned'),
        completeAccountCount: count(metrics.completeAccountCount),
        completeBranchSampleCounts: Object.fromEntries([...branchKeys].map((key) => [key,
          count(metrics.completeBranchTrainingSamples?.[key]) + count(metrics.completeBranchValidationSamples?.[key])])),
        completeBranchAccountCounts: metrics.completeBranchAccounts || {},
        qualityWarnings: metrics.qualityWarnings || []
      }]
    })
  }

  function distributedModel(configuration) {
    const selected = configuration?.resonance?.model
    if (!selected) return null
    const models = publishedModels()
    const current = models.find(model => model.id === selected.id)
    if (!current) return null
    const latest = models[0]
    const selectedAt = Date.parse(configuration.updatedAt || current.release?.publishedAt)
    // A deliberate selection remains in effect until the next model publication.
    if (configuration.enabled === true && configuration.resonance.enabled === true
      && latest && Date.parse(latest.release?.publishedAt) > selectedAt) return latest
    return current
  }

  function publishedCoreMLArtifact(modelId) {
    const descriptor = publishedModels().find((model) => model.id === modelId)
    if (!descriptor) throw trainingError('MODEL_NOT_PUBLISHED', '请选择已发布的共鸣 S2 模型。', 404)
    const artifact = resolveStoredCoreMLArtifact(statements.selectArtifact.get(modelId), modelsDirectory)
    if (!artifact) throw trainingError('MODEL_ARTIFACT_UNAVAILABLE', '模型文件不可用，请重新发布模型后重试。', 503)
    return { ...artifact, model: descriptor, fileName: descriptor.fileName }
  }

  function modelArtifact(modelId) {
    const row = statements.selectModel.get(modelId)
    if (!row) throw trainingError('TRAINING_MODEL_NOT_FOUND', '训练模型不存在。', 404)
    return {
      ...hydrateStoredModel(row),
      artifact: parseJSON(row.artifact_json, {})
    }
  }

  function releaseNotesForModel(row) {
    const saved = statements.selectPublication.get(row.id)
    if (saved?.release_generator_version === RELEASE_NOTES_VERSION && saved.release_summary && saved.release_notes) {
      return { summary: saved.release_summary, notes: saved.release_notes }
    }
    const previous = statements.selectReleaseBaseline.get(row.id)
    return generateReleaseNotes(hydrateModel(row), hydrateModel(previous))
  }

  function hydrateStoredModel(row) {
    const model = hydrateModel(row)
    if (!model) return null
    const coreMLArtifact = resolveStoredCoreMLArtifact(
      statements.selectArtifact.get(model.id),
      modelsDirectory
    )
    return {
      ...model,
      fileName: modelDownloadFileName(row.created_at, row.version),
      release: hydrateModelRelease(statements.selectPublication.get(model.id)),
      releasePreview: releaseNotesForModel(row),
      coreMLArtifact: coreMLArtifact
        ? {
            format: coreMLArtifact.format,
            sha256: coreMLArtifact.sha256,
            byteCount: coreMLArtifact.byteCount,
            createdAt: coreMLArtifact.createdAt
          }
        : null
    }
  }

  async function ensureCoreMLArtifact(modelId) {
    const row = statements.selectModel.get(modelId)
    if (!row) throw trainingError('TRAINING_MODEL_NOT_FOUND', '训练模型不存在。', 404)
    const existing = resolveStoredCoreMLArtifact(statements.selectArtifact.get(modelId), modelsDirectory)
    if (existing) {
      return {
        ...existing,
        fileName: modelDownloadFileName(row.created_at, row.version),
        model: hydrateStoredModel(row)
      }
    }
    if (artifactRuns.has(modelId)) return artifactRuns.get(modelId)
    const run = (async () => {
      const exported = await createCoreMLArtifact({
        row,
        modelsDirectory,
        exportModel
      })
      statements.upsertArtifact.run(
        modelId,
        exported.format,
        exported.relativePath,
        exported.sha256,
        exported.byteCount,
        exported.createdAt
      )
      return { ...exported, model: hydrateStoredModel(row) }
    })()
    artifactRuns.set(modelId, run)
    try {
      return await run
    } finally {
      artifactRuns.delete(modelId)
    }
  }

  async function runTraining(jobId, actorId) {
    const run = activeRun
    try {
      updateJob(jobId, 'collecting', { progress: 0.03, startedAt: new Date().toISOString() })
      await immediate()
      ensureNotCancelled(run)
      const configuration = settingsFromJob(statements.selectJob.get(jobId))
      const collected = inspectDataset({
        includeVectors: true,
        targetMode: configuration.targetMode
      })
      if (collected.stats.trainableSamples < configuration.minimumSamples) {
        throw trainingError(
          'INSUFFICIENT_TRAINING_SAMPLES',
          `可训练样本不足：需要 ${configuration.minimumSamples}，当前 ${collected.stats.trainableSamples}。`,
          422
        )
      }
      assertRequiredTrainingBranches(collected.stats.branchSamples)
      const split = splitCalibrationExamples(collected.examples, configuration.validationPercent)
      const trainingBranches = new Set(split.training.map(trainingBranchKey))
      const missingTrainingBranches = REQUIRED_TRAINING_BRANCHES.filter(
        (branch) => !trainingBranches.has(branch)
      )
      if (missingTrainingBranches.length > 0) {
        throw trainingError(
          'INSUFFICIENT_BRANCH_COVERAGE',
          `训练集缺少分支：${missingTrainingBranches.join(', ')}。请补充对应方案样本。`,
          422
        )
      }
      updateJob(jobId, 'training', {
        progress: 0.08,
        sampleCount: collected.examples.length,
        trainingCount: split.training.length,
        validationCount: split.validation.length,
        datasetFingerprint: collected.stats.datasetFingerprint
      })
      const trained = await trainTinyModel({
        training: split.training,
        validation: split.validation,
        calibration: split.calibration,
        settings: configuration,
        isCancelled: () => run?.cancelled === true,
        onEpoch: ({ epoch, trainingLoss, validationLoss }) => {
          updateJob(jobId, 'training', {
            epoch,
            progress: 0.08 + (epoch / configuration.epochs) * 0.84,
            trainingLoss,
            validationLoss
          })
        }
      })
      ensureNotCancelled(run)
      updateJob(jobId, 'validating', { progress: 0.95 })
      await immediate()
      const completeTraining = split.training.filter((item) => item.x !== null)
      const completeValidation = split.validation.filter((item) => item.x !== null)
      const completeAccounts = new Set(
        [...completeTraining, ...completeValidation].map((item) => item.accountId)
      )
      const metrics = {
        initialTrainingLoss: trained.initialTrainingLoss,
        initialValidationLoss: trained.initialValidationLoss,
        trainingLoss: trained.trainingLoss,
        validationLoss: trained.validationLoss,
        trainingLossImprovement: trained.initialTrainingLoss - trained.trainingLoss,
        validationLossImprovement: trained.initialValidationLoss === null || trained.validationLoss === null
          ? null : trained.initialValidationLoss - trained.validationLoss,
        supervisedTrainingLoss: trained.supervisedTrainingLoss,
        legacyTrainingLoss: trained.legacyTrainingLoss,
        preferenceTrainingPairs: trained.preferenceTraining.count,
        preferenceValidationPairs: trained.preferenceValidation.count,
        preferenceTrainingAccuracy: trained.preferenceTraining.accuracy,
        preferenceValidationAccuracy: trained.preferenceValidation.accuracy,
        branchValidation: trained.branchValidation,
        confidenceCalibration: trained.confidenceCalibration,
        calibrationSamples: split.calibration.length,
        excludedUnresolvedTrackSamples: split.excludedUnresolvedTrackSamples,
        standardProfileCalibrationSamples: split.calibration.filter(item => item.tuningProfile === 'standard').length,
        spatialProfileCalibrationSamples: split.calibration.filter(item => item.tuningProfile === 'monoSpatialEnhancement').length,
        learningConditionedCalibrationSamples: split.calibration.filter(item => item.learningConditioned).length,
        deviceConditionedCalibrationSamples: split.calibration.filter(item => item.deviceConditioned).length,
        conditionValidation: trained.conditionValidation,
        architecture: MODEL_ARCHITECTURE,
        selectionValidationTracks: trained.selectionValidationTracks,
        selectionSource: trained.selectionSource,
        bestEpoch: trained.bestEpoch,
        epochsRun: trained.epochsRun,
        earlyStopped: trained.earlyStopped,
        optimizationSteps: trained.optimizationSteps,
        targetMode: configuration.targetMode,
        intentUnits: configuration.intentUnits,
        weightDecay: configuration.weightDecay,
        supervisedTotalWeight: trained.supervisedTotalWeight,
        legacyTotalWeight: trained.legacyTotalWeight,
        completeAccountCount: completeAccounts.size,
        legacyAccountCount: new Set(
          [...split.training, ...split.validation]
            .filter((item) => item.x === null)
            .map((item) => item.accountId)
        ).size,
        selfGeneratedSamplesExcluded: collected.stats.selfGeneratedSamples,
        selfGeneratedPlansExcluded: collected.stats.selfGeneratedPlans,
        manualCorrectedTrainingSamples: completeTraining.filter(
          (item) => item.manualCorrected
        ).length,
        completeBranchTrainingSamples: branchCounts(completeTraining),
        completeBranchValidationSamples: branchCounts(completeValidation),
        completeBranchAccounts: Object.fromEntries(ALL_TRAINING_BRANCHES.map((branch) => [
          branch,
          new Set(
            [...completeTraining, ...completeValidation]
              .filter((item) => trainingBranchKey(item) === branch)
              .map((item) => item.accountId)
          ).size
        ])),
        trainingSamples: split.training.length,
        validationSamples: split.validation.length,
        tenBandTrainingSamples: split.training.filter(
          (item) => item.graphicEQMode === 'tenBand'
        ).length,
        thirtyTwoBandTrainingSamples: split.training.filter(
          (item) => item.graphicEQMode === 'thirtyTwoBand'
        ).length,
        standardProfileTrainingSamples: split.training.filter(
          (item) => item.tuningProfile === 'standard'
        ).length,
        spatialProfileTrainingSamples: split.training.filter(
          (item) => item.tuningProfile === 'monoSpatialEnhancement'
        ).length,
        tenBandStandardTrainingSamples: split.training.filter(
          (item) => trainingBranchKey(item) === 'tenBand:standard'
        ).length,
        tenBandSpatialTrainingSamples: split.training.filter(
          (item) => trainingBranchKey(item) === 'tenBand:monoSpatialEnhancement'
        ).length,
        thirtyTwoBandStandardTrainingSamples: split.training.filter(
          (item) => trainingBranchKey(item) === 'thirtyTwoBand:standard'
        ).length,
        thirtyTwoBandSpatialTrainingSamples: split.training.filter(
          (item) => trainingBranchKey(item) === 'thirtyTwoBand:monoSpatialEnhancement'
        ).length,
        completeTrainingSamples: split.training.filter((item) => item.x !== null).length,
        styleConditionedTrainingSamples: split.training.filter(
          (item) => item.x !== null && item.styleConditioned
        ).length,
        temporallyConditionedTrainingSamples: split.training.filter(
          (item) => item.x !== null && item.temporallyConditioned
        ).length,
        learningConditionedTrainingSamples: split.training.filter(
          (item) => item.x !== null && item.learningConditioned
        ).length,
        deviceConditionedTrainingSamples: split.training.filter(
          (item) => item.x !== null && item.deviceConditioned
        ).length,
        distinctTrainingTracks: new Set(split.training
          .filter((item) => item.x !== null)
          .map((item) => item.trackGroup)).size,
        feedbackConfirmedTrainingSamples: split.training.filter(
          (item) => item.x !== null && item.sampleWeight >= 1
        ).length,
        legacyTrainingSamples: split.training.filter((item) => item.x === null).length,
        tenBandValidationSamples: split.validation.filter(
          (item) => item.graphicEQMode === 'tenBand'
        ).length,
        thirtyTwoBandValidationSamples: split.validation.filter(
          (item) => item.graphicEQMode === 'thirtyTwoBand'
        ).length,
        standardProfileValidationSamples: split.validation.filter(
          (item) => item.tuningProfile === 'standard'
        ).length,
        spatialProfileValidationSamples: split.validation.filter(
          (item) => item.tuningProfile === 'monoSpatialEnhancement'
        ).length,
        tenBandStandardValidationSamples: split.validation.filter(
          (item) => trainingBranchKey(item) === 'tenBand:standard'
        ).length,
        tenBandSpatialValidationSamples: split.validation.filter(
          (item) => trainingBranchKey(item) === 'tenBand:monoSpatialEnhancement'
        ).length,
        thirtyTwoBandStandardValidationSamples: split.validation.filter(
          (item) => trainingBranchKey(item) === 'thirtyTwoBand:standard'
        ).length,
        thirtyTwoBandSpatialValidationSamples: split.validation.filter(
          (item) => trainingBranchKey(item) === 'thirtyTwoBand:monoSpatialEnhancement'
        ).length,
        completeValidationSamples: split.validation.filter((item) => item.x !== null).length,
        styleConditionedValidationSamples: split.validation.filter(
          (item) => item.x !== null && item.styleConditioned
        ).length,
        temporallyConditionedValidationSamples: split.validation.filter(
          (item) => item.x !== null && item.temporallyConditioned
        ).length,
        learningConditionedValidationSamples: split.validation.filter(
          (item) => item.x !== null && item.learningConditioned
        ).length,
        deviceConditionedValidationSamples: split.validation.filter(
          (item) => item.x !== null && item.deviceConditioned
        ).length,
        distinctValidationTracks: new Set(split.validation
          .filter((item) => item.x !== null)
          .map((item) => item.trackGroup)).size,
        feedbackConfirmedValidationSamples: split.validation.filter(
          (item) => item.x !== null && item.sampleWeight >= 1
        ).length,
        legacyValidationSamples: split.validation.filter((item) => item.x === null).length,
        legacyPriorWeight: configuration.priorWeight,
        legacyPerSampleWeight: trained.legacyPerSampleWeight,
        legacyPriorBranches: trained.legacyPriorBranches,
        minimumTrackSampleWeight: trained.minimumTrackSampleWeight
      }
      metrics.qualityWarnings = qualityWarnings(metrics)
      const modelId = crypto.randomUUID()
      const createdAt = new Date().toISOString()
      const version = `${MODEL_VERSION_PREFIX}-${createdAt.replace(/[-:.TZ]/g, '').slice(0, 14)}-${modelId.slice(0, 8)}`
      const artifact = {
        schemaVersion: 1,
        modelFamily: MODEL_FAMILY,
        modelName: MODEL_NAME,
        architecture: MODEL_ARCHITECTURE,
        trainingStrategy: `joint-dual-band-profile-conditioned-family-balanced-${configuration.targetMode}-target-account-damped-legacy-prior-human-preference-residual-nonlinear-intent`,
        graphicEQModes: ['tenBand', 'thirtyTwoBand'],
        bandCounts: [10, 32],
        legacyPriorWeight: configuration.priorWeight,
        targetMode: configuration.targetMode,
        intentUnits: configuration.intentUnits,
        featureSchemaVersion: FEATURE_SCHEMA_VERSION,
        targetSchemaVersion: TARGET_SCHEMA_VERSION,
        featureNames,
        targetNames,
        inputNormalization: trained.inputNormalization,
        outputNormalization: trained.outputNormalization,
        confidenceCalibration: trained.confidenceCalibration,
        hiddenActivation: 'tanh',
        hiddenWeights: trained.hiddenWeights,
        hiddenBias: trained.hiddenBias,
        residualWeights: trained.residualWeights,
        residualBias: trained.residualBias,
        residualScale: Math.SQRT1_2,
        intentActivation: 'tanh',
        intentWeights: trained.intentWeights,
        intentBias: trained.intentBias,
        outputSkipWeights: trained.outputSkipWeights,
        outputHeadWeights: trained.outputHeadWeights,
        outputHeadBias: trained.outputHeadBias
      }
      const row = {
        id: modelId,
        version,
        feature_schema_version: FEATURE_SCHEMA_VERSION,
        target_schema_version: TARGET_SCHEMA_VERSION,
        artifact_json: JSON.stringify(artifact),
        metrics_json: JSON.stringify(metrics),
        dataset_fingerprint: collected.stats.datasetFingerprint,
        sample_count: collected.examples.length,
        created_by: cleanActor(actorId),
        created_at: createdAt
      }
      const exported = await createCoreMLArtifact({ row, modelsDirectory, exportModel })
      if (run?.cancelled) {
        try { fs.rmSync(exported.filePath, { force: true }) } catch (_) {}
        ensureNotCancelled(run)
      }
      database.exec('BEGIN IMMEDIATE')
      try {
        statements.insertModel.run(
          modelId,
          version,
          FEATURE_SCHEMA_VERSION,
          TARGET_SCHEMA_VERSION,
          row.artifact_json,
          row.metrics_json,
          collected.stats.datasetFingerprint,
          collected.examples.length,
          row.created_by,
          createdAt
        )
        statements.upsertArtifact.run(
          modelId,
          exported.format,
          exported.relativePath,
          exported.sha256,
          exported.byteCount,
          exported.createdAt
        )
        database.exec('COMMIT')
      } catch (error) {
        try { database.exec('ROLLBACK') } catch (_) {}
        try { fs.rmSync(exported.filePath, { force: true }) } catch (_) {}
        throw error
      }
      finishJob(jobId, 'completed', {
        progress: 1,
        epoch: trained.epochsRun,
        trainingLoss: trained.trainingLoss,
        validationLoss: trained.validationLoss,
        modelId
      })
    } catch (error) {
      if (error?.code === 'TRAINING_CANCELLED') {
        finishJob(jobId, 'cancelled', { errorMessage: null })
      } else {
        finishJob(jobId, 'failed', { errorMessage: error?.message || '训练失败。' })
      }
    } finally {
      if (activeRun?.id === jobId) activeRun = null
    }
  }

  function updateJob(jobId, state, patch = {}) {
    if (closed) return
    const current = statements.selectJob.get(jobId)
    if (!current) return
    // A job that already reached a terminal state (e.g. cancelled by the admin
    // while the worker was still winding down) must not be reopened.
    if (!ACTIVE_STATES.has(current.state) && ACTIVE_STATES.has(state)) return
    if (!ACTIVE_STATES.has(current.state) && state !== current.state) return
    const now = new Date().toISOString()
    statements.updateJob.run(
      state,
      clamp(Number(patch.progress ?? current.progress), 0, 1),
      integer(patch.epoch ?? current.epoch, 0, 10_000),
      integer(patch.sampleCount ?? current.sample_count, 0, Number.MAX_SAFE_INTEGER),
      integer(patch.trainingCount ?? current.training_count, 0, Number.MAX_SAFE_INTEGER),
      integer(patch.validationCount ?? current.validation_count, 0, Number.MAX_SAFE_INTEGER),
      finiteOrNull(patch.trainingLoss ?? current.training_loss),
      finiteOrNull(patch.validationLoss ?? current.validation_loss),
      patch.datasetFingerprint ?? current.dataset_fingerprint,
      Object.prototype.hasOwnProperty.call(patch, 'errorMessage') ? patch.errorMessage : current.error_message,
      patch.modelId ?? current.model_id,
      patch.startedAt ?? current.started_at,
      patch.finishedAt ?? current.finished_at,
      now,
      jobId
    )
  }

  function finishJob(jobId, state, patch = {}) {
    updateJob(jobId, state, {
      ...patch,
      progress: patch.progress ?? (state === 'completed' ? 1 : undefined),
      finishedAt: new Date().toISOString()
    })
  }

  function close() {
    if (activeRun) activeRun.cancelled = true
    closed = true
    try { database.exec('PRAGMA wal_checkpoint(TRUNCATE)') } catch (_) {}
    database.close()
  }

  return {
    databasePath,
    cloudDatabasePath: resolvedCloudDatabasePath,
    trainingSampleDatabasePath: resolvedSampleDatabasePath,
    cancelTraining,
    close,
    inspectDataset,
    modelArtifact,
    ensureCoreMLArtifact,
    publishModel,
    publishedModels,
    distributedModel,
    publishedCoreMLArtifact,
    settings,
    startTraining,
    status,
    updateSettings
  }
}

function collectDataset(cloudDatabasePath, {
  includeVectors = false,
  targetMode = 'population',
  trainingSampleDatabasePath = null
} = {}) {
  const resolvedTargetMode = TARGET_MODES.has(targetMode) ? targetMode : 'population'
  const empty = {
    snapshotCount: 0,
    contributingAccounts: 0,
    completeAccounts: 0,
    completeSamples: 0,
    styleConditionedSamples: 0,
    temporallyConditionedSamples: 0,
    learningConditionedSamples: 0,
    deviceConditionedSamples: 0,
    manualCorrectedSamples: 0,
    distinctTracks: 0,
    feedbackConfirmedSamples: 0,
    excludedOutcomeSamples: 0,
    selfGeneratedSamples: 0,
    selfGeneratedPlans: 0,
    trainableSamples: 0,
    totalPlans: 0,
    legacyPlans: 0,
    invalidSamples: 0,
    tenBandSamples: 0,
    thirtyTwoBandSamples: 0,
    standardProfileSamples: 0,
    spatialProfileSamples: 0,
    branchSamples: Object.fromEntries(ALL_TRAINING_BRANCHES.map((branch) => [branch, 0])),
    completeBranchSamples: Object.fromEntries(ALL_TRAINING_BRANCHES.map((branch) => [branch, 0])),
    targetMode: resolvedTargetMode,
    datasetFingerprint: null
  }
  // Samples arriving through the dedicated intake are grouped per account so
  // they can be joined with that account's plans. Accounts that only ever
  // uploaded samples (no playlist snapshot) are still visited afterwards.
  const externalSamples = loadExternalTrainingSamples(trainingSampleDatabasePath)
  const hasCloud = Boolean(cloudDatabasePath) && fs.existsSync(cloudDatabasePath)
  if (!hasCloud && externalSamples.size === 0) {
    return includeVectors ? { stats: empty, examples: [] } : { stats: empty }
  }
  const { DatabaseSync } = require('node:sqlite')
  // Snapshots are streamed one account at a time; loading all of them with
  // `.all()` held every snapshot string in memory at once.
  function * snapshotRows() {
    const visited = new Set()
    if (hasCloud) {
      const database = new DatabaseSync(cloudDatabasePath, { readOnly: true })
      try {
        for (const row of database.prepare('SELECT token_id, snapshot_json FROM cloud_snapshots').iterate()) {
          visited.add(String(row.token_id))
          yield { token_id: row.token_id, snapshot: parseJSON(row.snapshot_json, null) }
        }
      } finally {
        database.close()
      }
    }
    for (const tokenId of externalSamples.keys()) {
      if (!visited.has(tokenId)) yield { token_id: tokenId, snapshot: {} }
    }
  }
  let snapshotCount = 0
  const examples = []
  const fingerprints = []
  let contributingAccounts = 0
  let completeAccounts = 0
  let totalPlans = 0
  let invalidSamples = 0
  let completeSamples = 0
  let styleConditionedSamples = 0
  let temporallyConditionedSamples = 0
  let learningConditionedSamples = 0
  let deviceConditionedSamples = 0
  let manualCorrectedSamples = 0
  let feedbackConfirmedSamples = 0
  let excludedOutcomeSamples = 0
  let selfGeneratedSamples = 0
  let selfGeneratedPlans = 0
  let legacyPlans = 0
  let tenBandSamples = 0
  let thirtyTwoBandSamples = 0
  let standardProfileSamples = 0
  let spatialProfileSamples = 0
  const branchSamples = Object.fromEntries(
    ALL_TRAINING_BRANCHES.map((branch) => [branch, 0])
  )
  const completeBranchSamples = Object.fromEntries(
    ALL_TRAINING_BRANCHES.map((branch) => [branch, 0])
  )
  const distinctTrackGroups = new Set()

  for (const row of snapshotRows()) {
    const snapshot = row.snapshot
    if (!snapshot) continue
    snapshotCount += 1
    const ai = snapshot.aiEqualizer || {}
    const accountId = crypto.createHash('sha256').update(String(row.token_id)).digest('hex').slice(0, 16)
    const plans = new Map()
    const planSongIdentifiers = new Map()
    for (const proposal of Object.values(ai.cachedProposals || {})) {
      const id = normalizedProposalId(proposal)
      if (id) plans.set(id, proposal)
    }
    for (const [songIdentifier, entries] of Object.entries(ai.savedProposals || {})) {
      if (!Array.isArray(entries)) continue
      for (const entry of entries) {
        const proposal = entry?.proposal || entry
        const id = normalizedProposalId(proposal) || normalizedProposalId(entry)
        if (id) {
          plans.set(id, proposal)
          planSongIdentifiers.set(id, String(songIdentifier || ''))
        }
      }
    }
    // Merge embedded (legacy transport) and dedicated-intake samples; the
    // fresher outcome wins. A sample that arrived through the intake is its
    // own plan of record even when the account never uploaded a snapshot.
    const accountSampleMap = new Map()
    for (const sample of Object.values(ai.trainingSamples || {})) {
      const id = String(sample?.id || sample?.target?.id || '').toLowerCase()
      if (id) accountSampleMap.set(id, sample)
    }
    for (const sample of externalSamples.get(String(row.token_id)) || []) {
      const id = String(sample?.id || '').toLowerCase()
      if (!id) continue
      const current = accountSampleMap.get(id)
      if (!current || sampleFreshness(sample) >= sampleFreshness(current)) {
        accountSampleMap.set(id, sample)
      }
      if (!plans.has(id) && sample?.target) {
        plans.set(id, sample.target)
        planSongIdentifiers.set(id, String(sample.songIdentifier || ''))
      }
    }
    totalPlans += plans.size
    let accountSamples = 0
    let accountCompleteSamples = 0
    const handledPlanIds = new Set()
    for (const sample of accountSampleMap.values()) {
      const sampleMode = sampleGraphicEQMode(sample)
      const proposalId = String(sample?.id || sample?.target?.id || '').toLowerCase()
      if (isSelfGeneratedProposal(sample?.target)
        && !hasHumanCorrection(sample, bandCountForMode(sampleMode))) {
        selfGeneratedSamples += 1
        if (proposalId) handledPlanIds.add(proposalId)
        continue
      }
      const vector = trainingVectors(sample, { targetMode: resolvedTargetMode })
      if (!vector) {
        invalidSamples += 1
        continue
      }
      if (!plans.has(proposalId) || handledPlanIds.has(proposalId)) {
        invalidSamples += 1
        continue
      }
      handledPlanIds.add(proposalId)
      const deviceFingerprint = crypto.createHash('sha256')
        .update(JSON.stringify(sample.deviceContext || null))
        .digest('hex')
      fingerprints.push(
        `${row.token_id}:${proposalId}:${sample.capturedAt || ''}:${sample.feedback || 'unverified'}:${sample.outcomeUpdatedAt || ''}:${sample.schemaVersion || 0}:${vector.tuningProfile}:${resolvedTargetMode}:${vector.manualCorrected ? 'manual' : 'plain'}:${deviceFingerprint}`
      )
      if (vector.sampleWeight <= 0) {
        excludedOutcomeSamples += 1
        continue
      }
      if (sampleMode === 'thirtyTwoBand') thirtyTwoBandSamples += 1
      else tenBandSamples += 1
      if (vector.tuningProfile === 'monoSpatialEnhancement') spatialProfileSamples += 1
      else standardProfileSamples += 1
      const branch = trainingBranchKey({
        graphicEQMode: sampleMode,
        tuningProfile: vector.tuningProfile
      })
      branchSamples[branch] += 1
      completeBranchSamples[branch] += 1
      accountSamples += 1
      accountCompleteSamples += 1
      completeSamples += 1
      if (vector.styleConditioned) styleConditionedSamples += 1
      if (vector.temporallyConditioned) temporallyConditionedSamples += 1
      if (vector.learningConditioned) learningConditionedSamples += 1
      if (vector.deviceConditioned) deviceConditionedSamples += 1
      if (vector.manualCorrected) manualCorrectedSamples += 1
      if (vector.outcomeConfirmed) feedbackConfirmedSamples += 1
      const trackGroup = trainingGroupKey(sample.songIdentifier, proposalId)
      distinctTrackGroups.add(trackGroup)
      if (includeVectors) {
        examples.push({
          accountId,
          trackGroup,
          id: proposalId,
          graphicEQMode: sampleMode,
          tuningProfile: vector.tuningProfile,
          tuningIntensity: vector.tuningIntensity,
          source: 'complete',
          styleConditioned: vector.styleConditioned,
          temporallyConditioned: vector.temporallyConditioned,
          learningConditioned: vector.learningConditioned,
          deviceConditioned: vector.deviceConditioned,
          manualCorrected: vector.manualCorrected,
          sampleWeight: vector.sampleWeight,
          x: vector.x,
          y: vector.y,
          targetMask: vector.targetMask,
          rejectedY: vector.rejectedY,
          preferenceMask: vector.preferenceMask,
          populationPair: resolvedTargetMode === 'joint' && vector.learningConditioned
            && !isSelfGeneratedProposal(sample.target)
            ? trainingVectors({ ...sample, feedback: null, manualGainsDB: null }, { targetMode: 'population' }) : null
        })
      }
    }

    // Historical plans have usable targets but no retained measurement input.
    // Keep x null as their provenance marker; training later supplies only the
    // known mode/profile/intensity one-hot values over a neutral population input.
    for (const [proposalId, proposal] of plans) {
      if (handledPlanIds.has(proposalId)) continue
      if (isSelfGeneratedProposal(proposal)) {
        selfGeneratedPlans += 1
        continue
      }
      const proposalMode = proposalGraphicEQMode(proposal)
      const vector = proposalTargetVector(proposal)
      if (!vector) {
        invalidSamples += 1
        continue
      }
      if (proposalMode === 'thirtyTwoBand') thirtyTwoBandSamples += 1
      else tenBandSamples += 1
      const tuningProfile = proposalTuningProfile(proposal)
      if (tuningProfile === 'monoSpatialEnhancement') spatialProfileSamples += 1
      else standardProfileSamples += 1
      branchSamples[trainingBranchKey({ graphicEQMode: proposalMode, tuningProfile })] += 1
      accountSamples += 1
      legacyPlans += 1
      fingerprints.push(`${row.token_id}:${proposalId}:legacy-target:${tuningProfile}`)
      if (includeVectors) {
        const trackGroup = trainingGroupKey(planSongIdentifiers.get(proposalId), proposalId)
        examples.push({
          accountId,
          trackGroup,
          id: proposalId,
          graphicEQMode: proposalMode,
          tuningProfile,
          tuningIntensity: proposalTuningIntensity(proposal),
          source: 'legacy',
          styleConditioned: false,
          x: null,
          y: vector.y,
          targetMask: vector.targetMask
        })
      }
    }
    if (accountSamples > 0) contributingAccounts += 1
    if (accountCompleteSamples > 0) completeAccounts += 1
  }
  const datasetFingerprint = examples.length > 0 || fingerprints.length > 0
    ? crypto.createHash('sha256').update(fingerprints.sort().join('\n')).digest('hex')
    : null
  const stats = {
    snapshotCount,
    contributingAccounts,
    completeAccounts,
    completeSamples,
    styleConditionedSamples,
    temporallyConditionedSamples,
    learningConditionedSamples,
    deviceConditionedSamples,
    manualCorrectedSamples,
    distinctTracks: distinctTrackGroups.size,
    feedbackConfirmedSamples,
    excludedOutcomeSamples,
    selfGeneratedSamples,
    selfGeneratedPlans,
    trainableSamples: completeSamples + legacyPlans,
    totalPlans,
    legacyPlans,
    invalidSamples,
    tenBandSamples,
    thirtyTwoBandSamples,
    standardProfileSamples,
    spatialProfileSamples,
    branchSamples,
    completeBranchSamples,
    targetMode: resolvedTargetMode,
    datasetFingerprint
  }
  return includeVectors ? { stats, examples } : { stats }
}

function loadExternalTrainingSamples(databasePath) {
  const result = new Map()
  if (!databasePath || !fs.existsSync(databasePath)) return result
  const { DatabaseSync } = require('node:sqlite')
  const database = new DatabaseSync(databasePath, { readOnly: true })
  try {
    const statement = database.prepare('SELECT token_id, sample_json FROM training_samples ORDER BY token_id')
    for (const row of statement.iterate()) {
      const sample = parseJSON(row.sample_json, null)
      if (!sample) continue
      const tokenId = String(row.token_id)
      const list = result.get(tokenId) || []
      list.push(sample)
      result.set(tokenId, list)
    }
  } finally {
    database.close()
  }
  return result
}

function sampleFreshness(sample) {
  return String(sample?.outcomeUpdatedAt || sample?.capturedAt || '')
}

function trainingVectors(sample, { targetMode = 'population' } = {}) {
  const features = sample?.features
  const target = sample?.target
  if (!SUPPORTED_SAMPLE_SCHEMA_VERSIONS.has(Number(sample?.schemaVersion))
    || !features || !target
    || String(sample.id || '').toLowerCase() !== String(target.id || '').toLowerCase()) return null

  const sampleMode = sampleGraphicEQMode(sample)
  const bandCount = bandCountForMode(sampleMode)
  const selfGenerated = isSelfGeneratedProposal(target)
  if (selfGenerated && !hasHumanCorrection(sample, bandCount)) return null
  const genreVector = confidenceVector(
    features.genreScores,
    features.genreHints,
    genreFeatureValues
  )
  const instrumentVector = confidenceVector(
    features.instrumentScores,
    features.instrumentHints,
    instrumentFeatureValues
  )
  const sectionProfiles = fixedSectionProfiles(
    features.sectionBandEnergyDB,
    features.bandEnergyDB,
    bandCount
  )
  const temporalVector = [
    ...modeBandBranches(sampleMode, features.bandEnergySpreadDB || []),
    ...modeSectionBranches(sampleMode, sectionProfiles),
    finite(features.spectralCentroidP10Hz, finite(features.spectralCentroidHz)),
    finite(features.spectralCentroidP90Hz, finite(features.spectralCentroidHz)),
    finite(features.spectralRolloffP10Hz, finite(features.spectralRolloffHz)),
    finite(features.spectralRolloffP90Hz, finite(features.spectralRolloffHz)),
    finite(features.spectralFluxP90, finite(features.spectralFlux)),
    finite(features.rmsP10DBFS, finite(features.rmsDBFS) - finite(features.dynamicSpreadDB) / 2),
    finite(features.rmsP50DBFS, finite(features.rmsDBFS)),
    finite(features.rmsP90DBFS, finite(features.rmsDBFS) + finite(features.dynamicSpreadDB) / 2)
  ]
  // Population mode trains the shared model on the learning-free population
  // target so one account's private preference cannot become everyone's prior;
  // the on-device Agent keeps applying personal residuals afterwards.
  const personalizedMode = targetMode === 'personalized' || targetMode === 'joint'
  const hasPersonalizedTarget = Boolean(sample.personalizedTarget)
  const learningConditioned = personalizedMode
    && hasPersonalizedTarget
    && isActiveLearningContext(sample.learningContext)
  const learningVector = learningConditioned
    ? learningContextVector(sample.learningContext, sampleMode)
    : Array(learningConditionedFeatureNames.length).fill(0)
  const deviceConditioned = Boolean(sample.populationTarget || (learningConditioned && sample.personalizedTarget))
    && isDetailedDeviceContext(sample.deviceContext)
  const detailedDeviceVector = deviceConditioned
    ? deviceContextVector(sample.deviceContext)
    : Array(detailedDeviceFeatureNames.length).fill(0)
  const x = [
    ...modeBandBranches(sampleMode, features.bandEnergyDB),
    ...scalarFeatureNames.map((name) => finite(features[name])),
    ...fixedArray(features.chroma, 12),
    finite(features.vocalReference?.confidence),
    finite(features.vocalReference?.presence),
    finite(features.vocalReference?.warmth),
    finite(features.vocalReference?.brightness),
    finite(features.vocalReference?.airiness),
    finite(features.vocalReference?.dynamicExpression),
    ...booleanFeatureNames.map((name) => features[name] === true ? 1 : 0),
    ...modeBandBranches(sampleMode, sample.deviceContext?.referenceGainsDB || []),
    features.graphicEQMode === 'thirtyTwoBand' ? 1 : 0,
    ...genreVector,
    ...instrumentVector,
    ...oneHotVector(features.outputKind, outputKindFeatureValues, 'other'),
    ...oneHotVector(target.tuningIntensity, tuningIntensityFeatureValues, 'smart'),
    ...oneHotVector(target.tuningProfile, tuningProfileFeatureValues, 'standard'),
    ...temporalVector,
    ...learningVector,
    ...detailedDeviceVector
  ]
  const deviceFreeTarget = learningConditioned
    ? sample.personalizedTarget
    : sample.populationTarget || target
  const hasExplicitDeviceFreeTarget = learningConditioned || Boolean(sample.populationTarget)
  const targetVector = proposalTargetVector(deviceFreeTarget, { requireCompliance: true })
  if (!targetVector || targetVector.mode !== sampleMode
    || x.length !== featureNames.length || !x.every(Number.isFinite)) return null
  const deviceReference = resample(sample.deviceContext?.referenceGainsDB || [], bandCount)
  const y = [...targetVector.y]
  const gainOffset = sampleMode === 'thirtyTwoBand' ? 10 : 0
  if (!hasExplicitDeviceFreeTarget) {
    // Schema-v1 samples only retained the final compiled curve, so recover the
    // population track correction by removing the local device baseline. New
    // samples carry an explicitly compiled populationTarget without device or
    // private user-preference residuals and must not be adjusted a second time.
    for (let index = 0; index < bandCount; index += 1) {
      y[gainOffset + index] -= deviceReference[index]
    }
  }
  // A manual equalizer edit is the strongest label we have, but only as a
  // delta against what the listener actually heard (the final compiled
  // curve). Applying that delta to the device-free target keeps headphone
  // correction out of the label.
  const manualDelta = manualGainDelta(sample, bandCount)
  const manualCorrected = manualDelta !== null
  const rejectedY = manualCorrected ? [...y] : null
  const preferenceMask = y.map((_, index) => manualDelta
    && index >= gainOffset && index < gainOffset + bandCount
    && Math.abs(manualDelta[index - gainOffset]) > 0.05 ? 1 : 0)
  if (manualCorrected) {
    for (let index = 0; index < bandCount; index += 1) {
      y[gainOffset + index] = clamp(
        y[gainOffset + index] + manualDelta[index],
        -MANUAL_GAIN_DELTA_LIMIT_DB,
        MANUAL_GAIN_DELTA_LIMIT_DB
      )
    }
  }
  return {
    x,
    y,
    graphicEQMode: sampleMode,
    tuningProfile: proposalTuningProfile(target),
    tuningIntensity: proposalTuningIntensity(target),
    // A graphic-EQ edit does not endorse the model's other DSP predictions.
    targetMask: selfGenerated
      ? targetVector.targetMask.map((value, index) => index < 42 ? value : 0)
      : targetVector.targetMask,
    styleConditioned: genreVector.some(Boolean) || instrumentVector.some(Boolean),
    temporallyConditioned: hasTemporalTrackEvidence(features),
    learningConditioned,
    deviceConditioned,
    manualCorrected,
    rejectedY,
    preferenceMask,
    sampleWeight: trainingOutcomeWeight(sample, manualCorrected),
    outcomeConfirmed: ['positive', 'retained'].includes(String(sample.feedback || ''))
      || manualCorrected
  }
}

function proposalTargetVector(target, { requireCompliance = false } = {}) {
  const compliance = target?.skillCompliance
  const gains = target?.gains
  if (!target || !normalizedProposalId(target)
    || !Array.isArray(gains)
    || (gains.length !== 10 && gains.length !== 32)
    || !gains.every((value) => Number.isFinite(Number(value)))
    || (requireCompliance
      && (compliance?.accepted !== true || compliance?.localValidationApplied !== true))) return null

  const targetMode = proposalGraphicEQMode(target)
  if (gains.length !== bandCountForMode(targetMode)) return null
  const tenBandActive = targetMode === 'tenBand'
  const y = [
    ...(tenBandActive ? target.gains.map((value) => finite(value)) : Array(10).fill(0)),
    ...(tenBandActive ? Array(32).fill(0) : target.gains.map((value) => finite(value))),
    finite(target.preampDB),
    finite(target.tone?.bassGain),
    finite(target.tone?.trebleGain),
    finite(target.spatial?.surroundLevel),
    finite(target.spatial?.reverbLevel),
    finite(target.spatial?.stereoWidth, 1),
    ...enhanceTargetNames.map((name) => finite(target.enhance?.[name])),
    target.enhance?.isEnabled === true ? 1 : 0,
    target.calibration?.outputCalibrationEnabled === true ? 1 : 0,
    target.calibration?.loudnessMatchingEnabled === true ? 1 : 0,
    target.calibration?.smartSongCompensationEnabled === true ? 1 : 0,
    finite(target.professional?.processingIntensity),
    target.professional?.dynamicEQ?.enabled === true ? 1 : 0,
    target.professional?.multiband?.enabled === true ? 1 : 0,
    target.professional?.parametricEQ?.enabled === true ? 1 : 0,
    ...effectTargetNames.map((name) => finite(target.effects?.[name])),
    ...effectBooleanTargetNames.map((name) => target.effects?.[name] === true ? 1 : 0)
  ]
  const targetMask = [
    ...Array(10).fill(tenBandActive ? 1 : 0),
    ...Array(32).fill(tenBandActive ? 0 : 1),
    ...Array(50).fill(1)
  ]
  const details = professionalTargetVector(target.professional, targetMode)
  y.push(...details.values)
  targetMask.push(...details.mask)
  if (y.length !== targetNames.length || !y.every(Number.isFinite)) return null
  return {
    mode: targetMode,
    y,
    targetMask
  }
}

function professionalTargetVector(professional, mode) {
  const values = []
  const mask = []
  const append = (value, known) => {
    values.push(known ? value : 0)
    mask.push(known ? 1 : 0)
  }
  for (const [kind, slots, fields] of [
    ['dynamicEQ', 4, dynamicBandFields], ['parametricEQ', 6, ['frequency', 'gainDB', 'q']]
  ]) {
    const stage = professional?.[kind]
    const bands = Array.isArray(stage?.bands)
      ? [...stage.bands].sort((a, b) => finite(a?.frequency) - finite(b?.frequency)) : []
    for (let slot = 0; slot < slots; slot += 1) {
      const inBranch = mode !== 'thirtyTwoBand' || slot < 3
      const band = inBranch ? bands[slot] : null
      const valid = Boolean(band && fields.every((field) => Number.isFinite(band[field]))
        && (kind !== 'parametricEQ' || parametricTypes.includes(band.type)))
      append(valid ? 1 : 0, inBranch && (Array.isArray(stage?.bands) || stage?.enabled === false))
      if (kind === 'parametricEQ') {
        for (const type of parametricTypes) append(band?.type === type ? 1 : 0, valid)
      }
      for (const field of fields) append(band?.[field], valid)
    }
  }
  const multiband = professional?.multiband
  for (const field of ['lowCrossoverHz', 'highCrossoverHz', 'attackMS', 'releaseMS']) {
    append(multiband?.[field], Number.isFinite(multiband?.[field]))
  }
  for (const field of ['thresholdsDB', 'ratios', 'maxReductionDB']) {
    for (let slot = 0; slot < 3; slot += 1) {
      append(multiband?.[field]?.[slot], Number.isFinite(multiband?.[field]?.[slot]))
    }
  }
  return { values, mask }
}

function trainingBranchKey(item) {
  const mode = item?.graphicEQMode === 'thirtyTwoBand' ? 'thirtyTwoBand' : 'tenBand'
  const profile = item?.tuningProfile === 'monoSpatialEnhancement'
    ? 'monoSpatialEnhancement'
    : 'standard'
  return `${mode}:${profile}`
}

function assertRequiredTrainingBranches(branchSamples) {
  const missing = REQUIRED_TRAINING_BRANCHES.filter(
    (branch) => Number(branchSamples?.[branch] || 0) < 1
  )
  if (missing.length === 0) return
  throw trainingError(
    'INSUFFICIENT_BRANCH_COVERAGE',
    `训练数据缺少分支：${missing.join(', ')}。10 段标准与空间分支各需要至少一个方案；32 段有样本时自动参与训练。`,
    422
  )
}

const featureIndex = Object.fromEntries(featureNames.map((name, index) => [name, index]))
const tenBandBranchIndices = featureNames
  .map((name, index) => (name.startsWith('tenBand.') ? index : -1))
  .filter((index) => index >= 0)
const thirtyTwoBandBranchIndices = featureNames
  .map((name, index) => (name.startsWith('thirtyTwoBand.') ? index : -1))
  .filter((index) => index >= 0)
const learningFeatureIndices = featureNames
  .map((name, index) => (name.startsWith('learning.') ? index : -1))
  .filter((index) => index >= 0)

// Historical plans keep the population mean for every measurement they never
// recorded, but the branch, profile and intensity they were generated under are
// known and must look exactly like a real input of that kind: the inactive band
// branch is zero, learning context is off.
function legacyConditioningVector(item, statistics) {
  const raw = [...statistics.mean]
  const thirtyTwoBand = item.graphicEQMode === 'thirtyTwoBand'
  for (const index of (thirtyTwoBand ? tenBandBranchIndices : thirtyTwoBandBranchIndices)) raw[index] = 0
  for (const index of learningFeatureIndices) raw[index] = 0
  raw[featureIndex['graphicEQMode.thirtyTwoBand']] = thirtyTwoBand ? 1 : 0
  const spatial = item.tuningProfile === 'monoSpatialEnhancement'
  raw[featureIndex['tuningProfile.standard']] = spatial ? 0 : 1
  raw[featureIndex['tuningProfile.monoSpatialEnhancement']] = spatial ? 1 : 0
  const intensity = tuningIntensityFeatureValues.includes(item.tuningIntensity)
    ? item.tuningIntensity
    : 'smart'
  for (const value of tuningIntensityFeatureValues) {
    raw[featureIndex[`tuningIntensity.${value}`]] = value === intensity ? 1 : 0
  }
  return normalizeVector(raw, statistics)
}

function branchCounts(items) {
  const counts = Object.fromEntries(ALL_TRAINING_BRANCHES.map((branch) => [branch, 0]))
  for (const item of items) counts[trainingBranchKey(item)] += 1
  return counts
}

function qualityWarnings(metrics) {
  const warnings = []
  if ((metrics.completeTrainingSamples || 0) === 0) {
    warnings.push('NO_COMPLETE_SAMPLES')
  }
  if ((metrics.completeAccountCount || 0) < 2 && (metrics.completeTrainingSamples || 0) > 0) {
    warnings.push('SINGLE_ACCOUNT_COMPLETE_SAMPLES')
  }
  for (const branch of ALL_TRAINING_BRANCHES) {
    if ((metrics.completeBranchValidationSamples?.[branch] || 0) === 0) {
      warnings.push(`NO_HELD_OUT_COMPLETE_SAMPLES:${branch}`)
    }
    if (metrics.branchValidation?.[branch]?.improvesPrior === false) {
      warnings.push(`NO_IMPROVEMENT_OVER_PRIOR:${branch}`)
    }
  }
  for (const branch of ALL_TRAINING_BRANCHES) {
    if (metrics.confidenceCalibration?.branches?.[branch]?.status !== 'calibrated') {
      warnings.push(`INSUFFICIENT_CONFIDENCE_CALIBRATION:${branch}`)
    }
  }
  if (!metrics.preferenceValidationPairs) warnings.push('NO_HELD_OUT_HUMAN_PREFERENCE_PAIRS')
  if ((metrics.distinctValidationTracks || 0) < 16) warnings.push('SMALL_VALIDATION_SET')
  if (metrics.earlyStopped === false && (metrics.epochsRun || 0) >= 8) {
    warnings.push('NO_EARLY_STOP_TRIGGERED')
  }
  return warnings
}

function prepareTrainingSet({ training, validation, settings }) {
  // Split by track before expanding the paired targets. One recording has one
  // statistical vote, with and without personal context, in the same model.
  const expand = (items) => items.flatMap((item) => item.populationPair ? [
    item,
    { ...item, ...item.populationPair, populationPair: null, sampleWeight: item.sampleWeight }
  ] : [item])
  training = expand(training)
  validation = expand(validation)
  const supervised = training.filter((item) => item.x !== null)
  const legacy = training.filter((item) => item.x === null)
  const inputNormalization = normalization(supervised)
  // Output scale is estimated over every training target (masked per branch).
  // Estimating it from complete samples only left never-observed branches at
  // the 0.001 floor, which saturated every legacy 32-band target at the clip.
  const outputNormalization = outputScaling(
    training.map((item) => item.y),
    training.map((item) => item.targetMask),
    targetNames.length
  )

  const trackExampleCounts = new Map()
  const supervisedAccountCounts = new Map()
  for (const item of supervised) {
    const key = item.trackGroup || `proposal:${item.id}`
    trackExampleCounts.set(key, (trackExampleCounts.get(key) || 0) + 1)
    const account = item.accountId || 'unknown'
    const recordings = supervisedAccountCounts.get(account) || new Set()
    recordings.add(item.id || key)
    supervisedAccountCounts.set(account, recordings)
  }
  const legacyBranchCounts = new Map()
  const legacyAccountBranchCounts = new Map()
  for (const item of legacy) {
    const branch = trainingBranchKey(item)
    legacyBranchCounts.set(branch, (legacyBranchCounts.get(branch) || 0) + 1)
    const key = `${branch}|${item.accountId || 'unknown'}`
    legacyAccountBranchCounts.set(key, (legacyAccountBranchCounts.get(key) || 0) + 1)
  }

  // Raw weights: outcome quality, one vote per track, and sqrt damping per
  // account so a single prolific account cannot define the population.
  const rawSupervisedWeights = supervised.map((item) => {
    const track = trackExampleCounts.get(item.trackGroup || `proposal:${item.id}`) || 1
    const account = supervisedAccountCounts.get(item.accountId || 'unknown')?.size || 1
    return finite(item.sampleWeight, 0.45) / track / Math.sqrt(account)
  })
  const supervisedBranchMass = new Map()
  supervised.forEach((item, index) => {
    const branch = trainingBranchKey(item)
    supervisedBranchMass.set(branch, (supervisedBranchMass.get(branch) || 0) + rawSupervisedWeights[index])
  })
  // Balance observed branches after track/account damping. An absent branch
  // receives no invented measured examples and remains a population prior.
  supervised.forEach((item, index) => {
    rawSupervisedWeights[index] /= Math.sqrt(supervisedBranchMass.get(trainingBranchKey(item)) || 1)
  })
  const rawLegacyWeights = legacy.map((item) => {
    const branch = trainingBranchKey(item)
    const branchCount = legacyBranchCounts.get(branch) || 1
    const account = legacyAccountBranchCounts.get(`${branch}|${item.accountId || 'unknown'}`) || 1
    // Every observed branch receives an equal share of the prior mass.
    return (1 / legacyBranchCounts.size) / branchCount / Math.sqrt(account)
  })
  const rawSupervisedTotal = rawSupervisedWeights.reduce((sum, value) => sum + value, 0)
  const rawLegacyTotal = rawLegacyWeights.reduce((sum, value) => sum + value, 0)
  // Both groups average to weight 1; the optimiser mixes them per step with
  // the priorWeight ratio (see trainTinyModelSync). legacyTargetTotal is the
  // equivalent legacy mass per supervised epoch, reported for audit.
  const supervisedScale = rawSupervisedTotal > 0 ? supervised.length / rawSupervisedTotal : 0
  const legacyTargetTotal = supervised.length > 0
    ? settings.priorWeight * supervised.length
    : legacy.length
  const legacyScale = rawLegacyTotal > 0 ? legacy.length / rawLegacyTotal : 0

  const train = []
  supervised.forEach((item, index) => train.push({
    x: normalizeVector(item.x, inputNormalization),
    y: normalizeVector(item.y, outputNormalization),
    targetMask: item.targetMask || Array(targetNames.length).fill(1),
    rejectedY: item.rejectedY ? normalizeVector(item.rejectedY, outputNormalization) : null,
    preferenceMask: item.preferenceMask,
    sampleWeight: rawSupervisedWeights[index] * supervisedScale,
    isLegacy: false
  }))
  legacy.forEach((item, index) => train.push({
    x: legacyConditioningVector(item, inputNormalization),
    y: normalizeVector(item.y, outputNormalization),
    targetMask: item.targetMask || Array(targetNames.length).fill(1),
    sampleWeight: rawLegacyWeights[index] * legacyScale,
    isLegacy: true
  }))
  const validate = validation.map((item) => ({
    x: item.x === null
      ? legacyConditioningVector(item, inputNormalization)
      : normalizeVector(item.x, inputNormalization),
    y: normalizeVector(item.y, outputNormalization),
    targetMask: item.targetMask || Array(targetNames.length).fill(1),
    rejectedY: item.rejectedY ? normalizeVector(item.rejectedY, outputNormalization) : null,
    preferenceMask: item.preferenceMask,
    sampleWeight: 1,
    isLegacy: item.x === null
  }))
  for (const item of [...train, ...validate]) item.lossWeights = targetLossWeights(item.targetMask)
  return {
    train,
    validate,
    inputNormalization,
    outputNormalization,
    supervisedTotalWeight: supervised.length,
    legacyTotalWeight: legacyTargetTotal,
    legacyPerSampleWeight: legacy.length > 0 ? legacyTargetTotal / legacy.length : 0,
    legacyPriorBranches: legacyBranchCounts.size,
    minimumTrackSampleWeight: rawSupervisedWeights.length
      ? Math.min(...rawSupervisedWeights.map((value) => value * supervisedScale))
      : 1
  }
}

function initializeParameters(settings, random) {
  const inputWidth = featureNames.length
  const outputWidth = targetNames.length
  const hiddenUnits = settings.hiddenUnits
  const intentUnits = settings.intentUnits
  const uniform = (fanIn, fanOut) => {
    const limit = Math.sqrt(6 / (fanIn + fanOut))
    return () => (random() * 2 - 1) * limit
  }
  const matrix = (rows, columns, sampler) => Array.from({ length: rows }, () =>
    Array.from({ length: columns }, sampler))
  const parameters = {
    hiddenWeights: matrix(hiddenUnits, inputWidth, uniform(inputWidth, hiddenUnits)),
    hiddenBias: Array(hiddenUnits).fill(0),
    residualWeights: matrix(hiddenUnits, hiddenUnits, uniform(hiddenUnits, hiddenUnits)),
    residualBias: Array(hiddenUnits).fill(0),
    intentWeights: null,
    intentBias: null,
    outputHeadWeights: null,
    outputSkipWeights: null,
    outputHeadBias: Array(outputWidth).fill(0)
  }
  if (intentUnits > 0) {
    parameters.intentWeights = matrix(intentUnits, hiddenUnits, uniform(hiddenUnits, intentUnits))
    parameters.intentBias = Array(intentUnits).fill(0)
    parameters.outputHeadWeights = matrix(outputWidth, intentUnits, uniform(intentUnits, outputWidth))
    parameters.outputSkipWeights = matrix(outputWidth, hiddenUnits, uniform(hiddenUnits, outputWidth))
  } else {
    parameters.outputHeadWeights = matrix(outputWidth, hiddenUnits, uniform(hiddenUnits, outputWidth))
  }
  return parameters
}

function forward(parameters, x) {
  const firstHidden = parameters.hiddenWeights.map((weights, index) =>
    Math.tanh(parameters.hiddenBias[index] + dot(weights, x)))
  const residual = parameters.residualWeights.map((weights, index) =>
    Math.tanh(parameters.residualBias[index] + dot(weights, firstHidden)))
  const hidden = firstHidden.map((value, index) => (value + residual[index]) * Math.SQRT1_2)
  const intent = parameters.intentWeights
    ? parameters.intentWeights.map((weights, index) => Math.tanh(parameters.intentBias[index] + dot(weights, hidden)))
    : hidden
  const prediction = parameters.outputHeadWeights.map((weights, index) =>
    parameters.outputHeadBias[index] + dot(weights, intent)
      + (parameters.outputSkipWeights ? dot(parameters.outputSkipWeights[index], hidden) : 0))
  return { firstHidden, residual, hidden, intent, prediction }
}

function zeroLike(parameters) {
  const zeros = (value) => Array.isArray(value[0])
    ? value.map((row) => Array(row.length).fill(0))
    : Array(value.length).fill(0)
  return {
    hiddenWeights: zeros(parameters.hiddenWeights),
    hiddenBias: zeros(parameters.hiddenBias),
    residualWeights: zeros(parameters.residualWeights),
    residualBias: zeros(parameters.residualBias),
    intentWeights: parameters.intentWeights ? zeros(parameters.intentWeights) : null,
    intentBias: parameters.intentBias ? zeros(parameters.intentBias) : null,
    outputHeadWeights: zeros(parameters.outputHeadWeights),
    outputSkipWeights: parameters.outputSkipWeights ? zeros(parameters.outputSkipWeights) : null,
    outputHeadBias: zeros(parameters.outputHeadBias)
  }
}

function accumulateGradients(parameters, gradients, item, batchSize) {
  const { firstHidden, residual, hidden, intent, prediction } = forward(parameters, item.x)
  const scale = item.sampleWeight / batchSize
  const preference = preferenceComparison(prediction, item)
  const outputGradient = prediction.map((value, index) => {
    if (item.targetMask[index] === 0) return 0
    const rankingGradient = preference?.violated && item.preferenceMask?.[index]
      ? 0.2 * 2 * (item.rejectedY[index] - item.y[index]) : 0
    return (2 * (value - item.y[index]) + rankingGradient) * scale * (item.lossWeights?.[index] ?? 1)
  })
  for (let output = 0; output < outputGradient.length; output += 1) {
    const gradient = outputGradient[output]
    if (gradient === 0) continue
    const row = gradients.outputHeadWeights[output]
    for (let index = 0; index < intent.length; index += 1) row[index] += gradient * intent[index]
    if (gradients.outputSkipWeights) {
      for (let index = 0; index < hidden.length; index += 1) {
        gradients.outputSkipWeights[output][index] += gradient * hidden[index]
      }
    }
    gradients.outputHeadBias[output] += gradient
  }
  let intentGradient = intent.map((_, index) => {
    let downstream = 0
    for (let output = 0; output < outputGradient.length; output += 1) {
      if (outputGradient[output] !== 0) {
        downstream += outputGradient[output] * parameters.outputHeadWeights[output][index]
      }
    }
    return parameters.intentWeights ? downstream * (1 - intent[index] ** 2) : downstream
  })
  if (parameters.intentWeights) {
    for (let unit = 0; unit < intentGradient.length; unit += 1) {
      const gradient = intentGradient[unit]
      if (gradient === 0) continue
      const row = gradients.intentWeights[unit]
      for (let index = 0; index < hidden.length; index += 1) row[index] += gradient * hidden[index]
      gradients.intentBias[unit] += gradient
    }
    intentGradient = hidden.map((_, index) => {
      let downstream = 0
      for (let unit = 0; unit < parameters.intentWeights.length; unit += 1) {
        downstream += intentGradient[unit] * parameters.intentWeights[unit][index]
      }
      return downstream
    })
  }
  const hiddenGradient = intentGradient.map((value, index) => {
    if (!parameters.outputSkipWeights) return value
    return value + outputGradient.reduce((sum, gradient, output) =>
      sum + gradient * parameters.outputSkipWeights[output][index], 0)
  })
  const residualGradient = hiddenGradient.map((value, index) =>
    value * Math.SQRT1_2 * (1 - residual[index] ** 2))
  for (let unit = 0; unit < residual.length; unit += 1) {
    for (let index = 0; index < firstHidden.length; index += 1) {
      gradients.residualWeights[unit][index] += residualGradient[unit] * firstHidden[index]
    }
    gradients.residualBias[unit] += residualGradient[unit]
  }
  for (let unit = 0; unit < hidden.length; unit += 1) {
    const upstream = hiddenGradient[unit] * Math.SQRT1_2 + residualGradient.reduce((sum, value, index) =>
      sum + value * parameters.residualWeights[index][unit], 0)
    const gradient = upstream * (1 - firstHidden[unit] ** 2)
    if (gradient === 0) continue
    const row = gradients.hiddenWeights[unit]
    const x = item.x
    for (let index = 0; index < x.length; index += 1) row[index] += gradient * x[index]
    gradients.hiddenBias[unit] += gradient
  }
}

function applyGradients(parameters, gradients, velocity, settings) {
  let squaredNorm = 0
  const visit = (value, fn) => {
    if (!value) return
    if (Array.isArray(value[0])) value.forEach((row) => row.forEach(fn))
    else value.forEach(fn)
  }
  for (const key of Object.keys(gradients)) visit(gradients[key], (g) => { squaredNorm += g * g })
  const clipScale = squaredNorm > GRADIENT_CLIP_NORM * GRADIENT_CLIP_NORM
    ? GRADIENT_CLIP_NORM / Math.sqrt(squaredNorm)
    : 1
  const update = (key, isWeight) => {
    const target = parameters[key]
    const gradient = gradients[key]
    const momentum = velocity[key]
    if (!target) return
    const step = (row, gradientRow, momentumRow) => {
      for (let index = 0; index < row.length; index += 1) {
        const decay = isWeight ? settings.weightDecay * row[index] : 0
        momentumRow[index] = MOMENTUM * momentumRow[index] + gradientRow[index] * clipScale + decay
        row[index] -= settings.learningRate * momentumRow[index]
      }
    }
    if (Array.isArray(target[0])) {
      for (let row = 0; row < target.length; row += 1) step(target[row], gradient[row], momentum[row])
    } else {
      step(target, gradient, momentum)
    }
  }
  update('hiddenWeights', true)
  update('hiddenBias', false)
  update('residualWeights', true)
  update('residualBias', false)
  update('intentWeights', true)
  update('intentBias', false)
  update('outputHeadWeights', true)
  update('outputSkipWeights', true)
  update('outputHeadBias', false)
}

function cloneParameters(parameters) {
  return JSON.parse(JSON.stringify(parameters))
}

function parameterLoss(examples, parameters, filter) {
  const selected = filter ? examples.filter(filter) : examples
  if (selected.length === 0) return null
  let total = 0
  let targetCount = 0
  for (const item of selected) {
    const { prediction } = forward(parameters, item.x)
    for (let index = 0; index < prediction.length; index += 1) {
      if (item.targetMask[index] === 0) continue
      const delta = prediction[index] - item.y[index]
      const weight = item.lossWeights?.[index] ?? 1
      total += delta * delta * weight
      targetCount += weight
    }
  }
  return total / Math.max(1, targetCount)
}

function preferenceComparison(prediction, item) {
  if (!item.rejectedY) return null
  let preferred = 0
  let rejected = 0
  let separation = 0
  let count = 0
  for (let index = 0; index < prediction.length; index += 1) {
    if (!item.preferenceMask?.[index] || !item.targetMask[index]) continue
    const weight = item.lossWeights?.[index] ?? 1
    preferred += (prediction[index] - item.y[index]) ** 2 * weight
    rejected += (prediction[index] - item.rejectedY[index]) ** 2 * weight
    separation += (item.y[index] - item.rejectedY[index]) ** 2 * weight
    count += 1
  }
  return count ? { preferred: preferred < rejected, violated: preferred + separation * 0.1 > rejected } : null
}

function preferenceMetrics(examples, parameters) {
  const pairs = examples.map((item) => preferenceComparison(forward(parameters, item.x).prediction, item))
    .filter(Boolean)
  return { count: pairs.length, accuracy: pairs.length ? pairs.filter((item) => item.preferred).length / pairs.length : null }
}

// Real held-out curves in dB, compared with this model's own population prior.
// No validation recordings means unknown, not a successful sensitivity test.
function evaluateGroups(examples, parameters, prepared, groups, belongs) {
  return Object.fromEntries(groups.map((group) => {
    const items = examples.filter((item) => item.x !== null && belongs(item, group))
    let error = 0
    let priorError = 0
    let count = 0
    const tracks = new Map()
    const families = new Map()
    for (const item of items) {
      const prediction = forward(parameters, normalizeVector(item.x, prepared.inputNormalization)).prediction
      const prior = forward(parameters, legacyConditioningVector(item, prepared.inputNormalization)).prediction
      const track = tracks.get(item.trackGroup || item.id) || { error: 0, count: 0 }
      for (let index = 0; index < targetNames.length; index += 1) {
        if (!item.targetMask[index]) continue
        const scale = prepared.outputNormalization.standardDeviation[index]
        const mean = prepared.outputNormalization.mean[index]
        const delta = prediction[index] * scale + mean - item.y[index]
        const family = targetFamily(targetNames[index])
        const score = families.get(family) || { squaredError: 0, targets: 0 }
        score.squaredError += (delta / scale) ** 2
        score.targets += 1
        families.set(family, score)
        if (index < 42) {
          error += Math.abs(delta)
          priorError += Math.abs(prior[index] * scale + mean - item.y[index])
          count += 1
          track.error += Math.abs(delta)
          track.count += 1
        }
      }
      if (track.count) tracks.set(item.trackGroup || item.id, track)
    }
    const trackErrors = [...tracks.values()].map((track) => track.error / track.count).sort((a, b) => a - b)
    return [group, {
      samples: items.length,
      tracks: tracks.size,
      eqMAEDB: count ? error / count : null,
      priorEQMAEDB: count ? priorError / count : null,
      improvesPrior: count ? error < priorError : null,
      // Empirical held-out error, not a per-song confidence or coverage promise.
      trackEQMAEP90DB: tracks.size >= MINIMUM_SELECTION_VALIDATION_SAMPLES
        ? trackErrors[Math.ceil(trackErrors.length * 0.9) - 1] : null,
      targetFamilyMSE: Object.fromEntries([...families.entries()].map(([name, score]) =>
        [name, score.squaredError / score.targets]))
    }]
  }))
}

function evaluateBranches(examples, parameters, prepared) {
  return evaluateGroups(examples, parameters, prepared, ALL_TRAINING_BRANCHES,
    (item, branch) => trainingBranchKey(item) === branch)
}

function evaluateConditions(examples, parameters, prepared) {
  const styles = genreFeatureValues.map((name) => `genreScore.${name}`)
  const devices = outputKindFeatureValues.map((name) => `outputKind.${name}`)
  return evaluateGroups(examples, parameters, prepared, [...styles, ...devices], (item, group) => {
    const names = group.startsWith('genreScore.') ? styles : devices
    if (!item.x) return false
    const values = names.map((name) => item.x[featureNames.indexOf(name)])
    const largest = Math.max(...values)
    // Ambiguous/tied style scores do not establish a measured genre label.
    return largest > 0 && values.filter((value) => value === largest).length === 1
      && item.x[featureNames.indexOf(group)] === largest
  })
}

// Synchronous core used by the worker thread (and by tests through the
// in-process fallback). `progress` is invoked once per epoch and may return
// false to cancel.
function trainTinyModelSync({ training, validation, calibration = [], settings, progress }) {
  assertCalibrationIsolation(training, validation, calibration)
  const prepared = prepareTrainingSet({ training, validation, settings })
  const { train, validate } = prepared
  const random = seededRandom(0x4d4f4e4f)
  let parameters = initializeParameters(settings, random)
  for (let index = 0; index < targetNames.length; index += 1) {
    if (!train.some((item) => item.targetMask[index])) {
      parameters.outputHeadWeights[index].fill(0)
      parameters.outputSkipWeights?.[index].fill(0)
      parameters.outputHeadBias[index] = 0
    }
  }
  const velocity = zeroLike(parameters)
  const supervisedFilter = (item) => !item.isLegacy
  const legacyFilter = (item) => item.isLegacy
  const initialTrainingLoss = parameterLoss(train, parameters) ?? 0
  const initialValidationLoss = parameterLoss(validate, parameters)
  // Early stopping tracks held-out complete samples once there are enough of
  // them to be a signal; a handful of validation tracks would otherwise stop
  // the population prior long before it converges.
  const supervisedValidationCount = new Set(validation.filter((item) => item.x !== null)
    .map((item) => item.trackGroup || item.id)).size
  const selectionLoss = () => {
    if (supervisedValidationCount >= MINIMUM_SELECTION_VALIDATION_SAMPLES) {
      return parameterLoss(validate, parameters, supervisedFilter) ?? 0
    }
    return parameterLoss(train, parameters) ?? 0
  }
  let best = { loss: selectionLoss(), epoch: 0, parameters: cloneParameters(parameters) }
  let optimizationSteps = 0
  let epochsRun = 0
  let earlyStopped = false
  let staleEpochs = 0
  // Stratified batches: every step sees both groups. Within a group the
  // per-sample weights average to 1, so a step's gradient mass is
  // supervised + priorWeight × legacy regardless of how lopsided the counts
  // are (6 complete samples against 6,000 plans must not starve either side).
  const supervisedTrain = train.filter(supervisedFilter)
  const legacyTrain = train.filter(legacyFilter)
  const groupBatch = (group, share) => group.length === 0
    ? 0
    : Math.max(1, Math.min(group.length, Math.floor(settings.batchSize * share), Math.floor(train.length / 16) || 1))
  const bothGroups = supervisedTrain.length > 0 && legacyTrain.length > 0
  const supervisedBatch = groupBatch(supervisedTrain, bothGroups ? 0.5 : 1)
  const legacyBatch = groupBatch(legacyTrain, bothGroups ? 0.5 : 1)
  const stepsPerEpoch = Math.max(
    supervisedBatch ? Math.ceil(supervisedTrain.length / supervisedBatch) : 0,
    legacyBatch ? Math.ceil(legacyTrain.length / legacyBatch) : 0
  )
  const supervisedMass = bothGroups ? 1 / (1 + settings.priorWeight) : 1
  const legacyMass = bothGroups ? settings.priorWeight / (1 + settings.priorWeight) : 1
  const cursor = (group) => ({ group, offset: 0 })
  const supervisedCursor = cursor(supervisedTrain)
  const legacyCursor = cursor(legacyTrain)
  const take = (state, count) => {
    const items = []
    while (items.length < count && state.group.length) {
      if (state.offset >= state.group.length) {
        deterministicShuffle(state.group, random)
        state.offset = 0
      }
      items.push(state.group[state.offset])
      state.offset += 1
    }
    return items
  }
  deterministicShuffle(supervisedTrain, random)
  deterministicShuffle(legacyTrain, random)
  for (let epoch = 1; epoch <= settings.epochs; epoch += 1) {
    for (let step = 0; step < stepsPerEpoch; step += 1) {
      const gradients = zeroLike(parameters)
      const supervisedItems = take(supervisedCursor, supervisedBatch)
      const legacyItems = take(legacyCursor, legacyBatch)
      for (const item of supervisedItems) {
        accumulateGradients(parameters, gradients, item, supervisedItems.length / supervisedMass)
      }
      for (const item of legacyItems) {
        accumulateGradients(parameters, gradients, item, legacyItems.length / legacyMass)
      }
      applyGradients(parameters, gradients, velocity, settings)
      optimizationSteps += 1
    }
    epochsRun = epoch
    const trainingLoss = parameterLoss(train, parameters) ?? 0
    const validationLoss = parameterLoss(validate, parameters)
    const current = selectionLoss()
    if (current < best.loss - 1e-6) {
      best = { loss: current, epoch, parameters: cloneParameters(parameters) }
      staleEpochs = 0
    } else {
      staleEpochs += 1
    }
    if (progress && progress({ epoch, trainingLoss, validationLoss }) === false) {
      throw trainingError('TRAINING_CANCELLED', '训练已取消。', 409)
    }
    if (settings.earlyStoppingPatience > 0 && staleEpochs >= settings.earlyStoppingPatience) {
      earlyStopped = true
      break
    }
  }
  parameters = best.parameters
  return {
    ...parameters,
    architecture: MODEL_ARCHITECTURE,
    residualScale: Math.SQRT1_2,
    intentActivation: 'tanh',
    inputNormalization: prepared.inputNormalization,
    outputNormalization: prepared.outputNormalization,
    initialTrainingLoss,
    initialValidationLoss,
    trainingLoss: parameterLoss(train, parameters) ?? 0,
    validationLoss: parameterLoss(validate, parameters),
    supervisedTrainingLoss: parameterLoss(train, parameters, supervisedFilter),
    legacyTrainingLoss: parameterLoss(train, parameters, legacyFilter),
    bestEpoch: best.epoch,
    epochsRun,
    earlyStopped,
    selectionValidationTracks: supervisedValidationCount,
    selectionSource: supervisedValidationCount >= MINIMUM_SELECTION_VALIDATION_SAMPLES ? 'heldOutTracks' : 'trainingLoss',
    optimizationSteps,
    supervisedTotalWeight: prepared.supervisedTotalWeight,
    legacyTotalWeight: prepared.legacyTotalWeight,
    legacyPerSampleWeight: prepared.legacyPerSampleWeight,
    legacyPriorBranches: prepared.legacyPriorBranches,
    minimumTrackSampleWeight: prepared.minimumTrackSampleWeight,
    preferenceTraining: preferenceMetrics(train, parameters),
    preferenceValidation: preferenceMetrics(validate, parameters),
    branchValidation: evaluateBranches(validation, parameters, prepared),
    conditionValidation: evaluateConditions(validation, parameters, prepared),
    confidenceCalibration: calibrateConfidence({ training, validation, calibration, parameters, prepared })
  }
}

// Runs the optimisation off the event loop so a multi-minute job cannot stall
// the admin API. Cancellation is a shared flag the worker polls each epoch.
function trainTinyModel({ training, validation, calibration = [], settings, isCancelled, onEpoch }) {
  if (settings.inProcess === true) {
    return Promise.resolve().then(() => trainTinyModelSync({
      training,
      validation,
      calibration,
      settings,
      progress: (event) => {
        onEpoch?.(event)
        return !isCancelled?.()
      }
    }))
  }
  return new Promise((resolve, reject) => {
    const cancelFlag = new Int32Array(new SharedArrayBuffer(4))
    const worker = new Worker(__filename, {
      workerData: { audioTuningTrainer: true, training, validation, calibration, settings, cancelFlag }
    })
    let settled = false
    let cancelRequestedAt = null
    const finish = (fn) => (value) => {
      if (settled) return
      settled = true
      clearInterval(poll)
      fn(value)
    }
    // Ask politely first (checked once per epoch); hard-terminate if the
    // worker does not wind down within a second.
    const poll = setInterval(() => {
      if (!isCancelled?.()) return
      Atomics.store(cancelFlag, 0, 1)
      cancelRequestedAt ??= Date.now()
      if (Date.now() - cancelRequestedAt > 1_000) {
        worker.terminate().catch(() => {})
        finish(reject)(trainingError('TRAINING_CANCELLED', '训练已取消。', 409))
      }
    }, 250)
    worker.on('message', (message) => {
      if (message?.type === 'epoch') onEpoch?.(message)
      else if (message?.type === 'done') finish(resolve)(message.result)
      else if (message?.type === 'error') {
        const error = new Error(message.message)
        if (message.code) error.code = message.code
        if (message.statusCode) error.statusCode = message.statusCode
        finish(reject)(error)
      }
    })
    worker.on('error', finish(reject))
    worker.on('exit', (code) => {
      if (!settled) finish(reject)(new Error(`训练线程异常退出：${code}`))
    })
  })
}


function installAudioTuningTrainingRoutes({
  app,
  service,
  authMiddleware,
  authorize,
  resolvePublicToken,
  audit,
  logger = console
}) {
  if (typeof authMiddleware !== 'function' || typeof authorize !== 'function') return
  const protectedRoute = [authMiddleware, authorize('training.manage')]

  app.get('/api/audio-training/models', ...protectedRoute, route(async (_req, res) => {
    res.setHeader('Cache-Control', 'private, no-store')
    res.json({ ok: true, models: service.publishedModels() })
  }, logger))

  if (typeof resolvePublicToken === 'function') {
    app.get('/api/public/audio-training/models/:modelId/coreml', route(async (req, res) => {
      const access = resolvePublicToken(req, res)
      if (!access) return
      const configuration = access.data.aiProviderConfig
      const selection = configuration?.resonance
      const distributed = service.distributedModel(configuration)
      if (configuration?.enabled !== true || selection?.enabled !== true || distributed?.id !== req.params.modelId) {
        throw trainingError('MODEL_NOT_DISTRIBUTED', '此模型尚未启用分发，请刷新调音服务后重试。', 403)
      }
      const artifact = service.publishedCoreMLArtifact(req.params.modelId)
      if (artifact.sha256 !== distributed.sha256) {
        throw trainingError('MODEL_CHANGED', '模型已更新，请重新发布调音服务配置。', 409)
      }
      await sendCoreMLArtifact(res, artifact)
    }, logger))
  }

  app.get('/api/audio-training', ...protectedRoute, route(async (_req, res) => {
    res.json({ ok: true, ...service.status() })
  }, logger))

  app.put('/api/audio-training/settings', ...protectedRoute, route(async (req, res) => {
    const value = service.updateSettings(req.body)
    audit?.({
      actorId: actor(req),
      action: 'audio_training.settings.update',
      resourceType: 'audio_training_settings',
      resourceId: 'global',
      after: value
    })
    res.json({ ok: true, settings: value })
  }, logger))

  app.post('/api/audio-training/jobs', ...protectedRoute, route(async (req, res) => {
    const job = service.startTraining(actor(req))
    audit?.({
      actorId: actor(req),
      action: 'audio_training.start',
      resourceType: 'audio_training_job',
      resourceId: job.id,
      metadata: { sampleCount: service.inspectDataset().trainableSamples }
    })
    res.status(202).json({ ok: true, job })
  }, logger))

  app.post('/api/audio-training/jobs/:jobId/cancel', ...protectedRoute, route(async (req, res) => {
    const job = service.cancelTraining(req.params.jobId)
    audit?.({
      actorId: actor(req),
      action: 'audio_training.cancel',
      resourceType: 'audio_training_job',
      resourceId: job.id
    })
    res.json({ ok: true, job })
  }, logger))

  app.post('/api/audio-training/models/:modelId/publish', ...protectedRoute, route(async (req, res) => {
    if (req.body?.confirmed !== true) {
      throw trainingError('CONFIRMATION_REQUIRED', '发布模型需要明确确认。', 400)
    }
    const model = await service.publishModel(req.params.modelId, actor(req))
    audit?.({
      actorId: actor(req),
      action: 'audio_training.publish',
      resourceType: 'audio_training_model',
      resourceId: model.id
    })
    res.json({ ok: true, model })
  }, logger))

  app.get('/api/audio-training/models/:modelId', ...protectedRoute, route(async (req, res) => {
    res.json({ ok: true, model: service.modelArtifact(req.params.modelId) })
  }, logger))

  app.get('/api/audio-training/models/:modelId/coreml', ...protectedRoute, route(async (req, res) => {
    const artifact = await service.ensureCoreMLArtifact(req.params.modelId)
    audit?.({
      actorId: actor(req),
      action: 'audio_training.model.download',
      resourceType: 'audio_training_model',
      resourceId: req.params.modelId,
      metadata: { format: artifact.format, sha256: artifact.sha256 }
    })
    await sendCoreMLArtifact(res, artifact)
  }, logger))
}

async function createCoreMLArtifact({ row, modelsDirectory, exportModel }) {
  const model = hydrateModel(row)
  const artifact = parseJSON(row.artifact_json, null)
  if (!model || !artifact) {
    throw trainingError('COREML_EXPORT_FAILED', '训练快照损坏，无法生成 Core ML 模型。', 500)
  }
  const fileComponent = safeFileComponent(model.id)
  const relativePath = `${fileComponent}.mlmodel`
  const filePath = path.join(modelsDirectory, relativePath)
  const unique = crypto.randomUUID()
  const sourcePath = path.join(modelsDirectory, `.${fileComponent}-${unique}.json`)
  const temporaryPath = path.join(modelsDirectory, `.${fileComponent}-${unique}.mlmodel`)
  try {
    fs.writeFileSync(
      sourcePath,
      JSON.stringify({ ...model, artifact }),
      { encoding: 'utf8', mode: 0o600 }
    )
    await exportModel({ sourcePath, outputPath: temporaryPath })
    const stat = fs.statSync(temporaryPath)
    if (!stat.isFile() || stat.size < 256 || stat.size > 50 * 1024 * 1024) {
      throw trainingError('COREML_EXPORT_FAILED', 'Core ML 模型文件无效。', 500)
    }
    const sha256 = crypto.createHash('sha256').update(fs.readFileSync(temporaryPath)).digest('hex')
    fs.renameSync(temporaryPath, filePath)
    return {
      format: CORE_ML_ARTIFACT_FORMAT,
      relativePath,
      filePath,
      fileName: modelDownloadFileName(model.createdAt, model.version),
      sha256,
      byteCount: stat.size,
      createdAt: new Date().toISOString()
    }
  } catch (error) {
    if (error?.code === 'COREML_EXPORT_FAILED') throw error
    throw trainingError(
      'COREML_EXPORT_FAILED',
      `Core ML 模型生成失败：${cleanExporterError(error)}`,
      500
    )
  } finally {
    try { fs.rmSync(sourcePath, { force: true }) } catch (_) {}
    try { fs.rmSync(temporaryPath, { force: true }) } catch (_) {}
  }
}

function exportCoreMLViaPython({ pythonPath, exporterPath, sourcePath, outputPath }) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      pythonPath,
      [exporterPath, '--source', sourcePath, '--output', outputPath],
      { stdio: ['ignore', 'ignore', 'pipe'] }
    )
    let stderr = ''
    const timeout = setTimeout(() => {
      child.kill('SIGKILL')
      reject(new Error('导出进程超时。'))
    }, 120_000)
    child.stderr.on('data', (chunk) => {
      stderr = `${stderr}${chunk}`.slice(-8_000)
    })
    child.once('error', (error) => {
      clearTimeout(timeout)
      reject(error)
    })
    child.once('close', (code, signal) => {
      clearTimeout(timeout)
      if (code === 0) resolve()
      else reject(new Error(stderr.trim() || `导出进程退出：${code ?? signal ?? 'unknown'}`))
    })
  })
}

function resolveStoredCoreMLArtifact(row, modelsDirectory) {
  if (!row) return null
  if (row.format !== CORE_ML_ARTIFACT_FORMAT) return null
  const relativePath = String(row.relative_path || '')
  if (!relativePath || path.basename(relativePath) !== relativePath) return null
  const filePath = path.join(modelsDirectory, relativePath)
  try {
    const stat = fs.statSync(filePath)
    if (!stat.isFile() || stat.size !== Number(row.byte_count)) return null
    const sha256 = crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')
    if (sha256 !== row.sha256) return null
    return {
      ...hydrateCoreMLArtifact(row),
      relativePath,
      filePath
    }
  } catch (_) {
    return null
  }
}

function hydrateCoreMLArtifact(row) {
  if (!row) return null
  return {
    format: row.format,
    sha256: row.sha256,
    byteCount: Number(row.byte_count),
    createdAt: row.created_at
  }
}

function sendCoreMLArtifact(res, artifact) {
  res.setHeader('Content-Type', 'application/vnd.apple.coreml-model')
  res.setHeader('Cache-Control', 'private, no-store')
  res.setHeader('X-Mono-Model-SHA256', artifact.sha256)
  res.setHeader('X-Mono-Model-Version', artifact.model.version)
  res.setHeader('X-Mono-Feature-Schema', String(artifact.model.featureSchemaVersion))
  res.setHeader('X-Mono-Target-Schema', String(artifact.model.targetSchemaVersion))
  res.download(artifact.filePath, artifact.fileName)
}

function safeFileComponent(value) {
  const result = String(value || '').replace(/[^a-zA-Z0-9_-]/g, '-').slice(0, 160)
  if (!result) throw trainingError('COREML_EXPORT_FAILED', '模型标识无效。', 500)
  return result
}

function cleanExporterError(error) {
  return String(error?.message || error || '未知错误').replace(/\s+/g, ' ').trim().slice(0, 500)
}

function prepareStatements(database) {
  return {
    selectSettings: database.prepare('SELECT * FROM audio_training_settings WHERE singleton = 1'),
    updateSettings: database.prepare(`UPDATE audio_training_settings SET epochs = ?, hidden_units = ?,
      learning_rate = ?, validation_percent = ?, minimum_samples = ?, prior_weight = ?, weight_decay = ?,
      early_stopping_patience = ?, intent_units = ?, target_mode = ?, updated_at = ? WHERE singleton = 1`),
    insertJob: database.prepare(`INSERT INTO audio_training_jobs
      (id, state, progress, epoch, total_epochs, settings_json, created_by, created_at, updated_at)
      VALUES (?, 'queued', 0, 0, ?, ?, ?, ?, ?)`),
    selectJob: database.prepare('SELECT * FROM audio_training_jobs WHERE id = ?'),
    selectLatestJob: database.prepare('SELECT * FROM audio_training_jobs ORDER BY created_at DESC LIMIT 1'),
    selectActiveJob: database.prepare(`SELECT * FROM audio_training_jobs
      WHERE state IN ('queued', 'collecting', 'training', 'validating') ORDER BY created_at DESC LIMIT 1`),
    updateJob: database.prepare(`UPDATE audio_training_jobs SET state = ?, progress = ?, epoch = ?,
      sample_count = ?, training_count = ?, validation_count = ?, training_loss = ?, validation_loss = ?,
      dataset_fingerprint = ?, error_message = ?, model_id = ?, started_at = ?, finished_at = ?, updated_at = ?
      WHERE id = ?`),
    insertModel: database.prepare(`INSERT INTO audio_training_models
      (id, version, feature_schema_version, target_schema_version, artifact_json, metrics_json,
       dataset_fingerprint, sample_count, created_by, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`),
    selectModel: database.prepare('SELECT * FROM audio_training_models WHERE id = ?'),
    selectLatestModel: database.prepare('SELECT * FROM audio_training_models ORDER BY created_at DESC LIMIT 1'),
    selectPublishedModel: database.prepare(`SELECT m.* FROM audio_training_model_publication p
      JOIN audio_training_models m ON m.id = p.model_id WHERE p.singleton = 1`),
    selectPublication: database.prepare('SELECT * FROM audio_training_published_models WHERE model_id = ?'),
    selectReleaseBaseline: database.prepare(`SELECT m.* FROM audio_training_published_models p
      JOIN audio_training_models m ON m.id = p.model_id WHERE m.id != ? ORDER BY p.published_at DESC, m.id LIMIT 1`),
    selectPublishedModels: database.prepare(`SELECT m.*, p.published_at, p.release_summary, p.release_notes, p.release_generator_version FROM audio_training_published_models p
      JOIN audio_training_models m ON m.id = p.model_id ORDER BY p.published_at DESC, m.id`),
    recordPublication: database.prepare(`INSERT INTO audio_training_published_models (model_id, published_at, release_summary, release_notes, release_generator_version)
      VALUES (?, ?, ?, ?, ?) ON CONFLICT(model_id) DO UPDATE SET published_at = excluded.published_at,
      release_summary = excluded.release_summary, release_notes = excluded.release_notes,
      release_generator_version = excluded.release_generator_version`),
    publishModel: database.prepare(`INSERT INTO audio_training_model_publication
      (singleton, model_id, published_by, published_at) VALUES (1, ?, ?, ?)
      ON CONFLICT(singleton) DO UPDATE SET model_id = excluded.model_id,
      published_by = excluded.published_by, published_at = excluded.published_at`),
    selectArtifact: database.prepare('SELECT * FROM audio_training_model_artifacts WHERE model_id = ?'),
    upsertArtifact: database.prepare(`INSERT INTO audio_training_model_artifacts
      (model_id, format, relative_path, sha256, byte_count, created_at) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(model_id) DO UPDATE SET format = excluded.format,
      relative_path = excluded.relative_path, sha256 = excluded.sha256,
      byte_count = excluded.byte_count, created_at = excluded.created_at`)
  }
}

function hydrateSettings(row) {
  return {
    ...normalizeSettings({
      epochs: row.epochs,
      hiddenUnits: row.hidden_units,
      learningRate: row.learning_rate,
      validationPercent: row.validation_percent,
      minimumSamples: row.minimum_samples,
      priorWeight: row.prior_weight,
      weightDecay: row.weight_decay,
      earlyStoppingPatience: row.early_stopping_patience,
      intentUnits: row.intent_units,
      targetMode: row.target_mode
    }),
    updatedAt: row.updated_at
  }
}

function normalizeSettings(raw) {
  return {
    epochs: integer(raw.epochs, 1, 200, 40),
    hiddenUnits: integer(raw.hiddenUnits, 4, 128, 64),
    learningRate: clamp(finite(raw.learningRate, 0.01), 0.0001, 0.1),
    validationPercent: integer(raw.validationPercent, 10, 40, 20),
    minimumSamples: integer(raw.minimumSamples, 4, 100_000, 32),
    // Ratio of total legacy-prior mass to total supervised mass per epoch.
    priorWeight: clamp(finite(raw.priorWeight, 1), 0.05, 4),
    weightDecay: clamp(finite(raw.weightDecay, 0.0001), 0, 0.01),
    earlyStoppingPatience: integer(raw.earlyStoppingPatience, 0, 50, 8),
    // Nonlinear intent path supplements the full-width residual output path.
    intentUnits: integer(raw.intentUnits, 0, 64, 32),
    targetMode: TARGET_MODES.has(raw.targetMode) ? raw.targetMode : 'joint',
    batchSize: 64
  }
}

function migrateSettingsTable(database) {
  const columns = new Set(
    database.prepare('PRAGMA table_info(audio_training_settings)').all().map((row) => row.name)
  )
  const defaults = normalizeSettings({})
  const additions = [
    ['prior_weight', `REAL NOT NULL DEFAULT ${defaults.priorWeight}`],
    ['weight_decay', `REAL NOT NULL DEFAULT ${defaults.weightDecay}`],
    ['early_stopping_patience', `INTEGER NOT NULL DEFAULT ${defaults.earlyStoppingPatience}`],
    ['intent_units', `INTEGER NOT NULL DEFAULT ${defaults.intentUnits}`],
    ['target_mode', `TEXT NOT NULL DEFAULT '${defaults.targetMode}'`]
  ]
  for (const [name, definition] of additions) {
    if (columns.has(name)) continue
    database.exec(`ALTER TABLE audio_training_settings ADD COLUMN ${name} ${definition}`)
  }
}

function hydrateJob(row) {
  if (!row) return null
  return {
    id: row.id,
    state: row.state,
    progress: Number(row.progress),
    epoch: Number(row.epoch),
    totalEpochs: Number(row.total_epochs),
    sampleCount: Number(row.sample_count),
    trainingCount: Number(row.training_count),
    validationCount: Number(row.validation_count),
    trainingLoss: finiteOrNull(row.training_loss),
    validationLoss: finiteOrNull(row.validation_loss),
    datasetFingerprint: row.dataset_fingerprint || null,
    errorMessage: row.error_message || null,
    modelId: row.model_id || null,
    createdBy: row.created_by || null,
    createdAt: row.created_at,
    startedAt: row.started_at || null,
    finishedAt: row.finished_at || null,
    updatedAt: row.updated_at,
    isActive: ACTIVE_STATES.has(row.state)
  }
}

function migrateReleaseNotes(database) {
  const outdated = database.prepare(`SELECT m.* FROM audio_training_published_models p
    JOIN audio_training_models m ON m.id = p.model_id
    WHERE p.release_generator_version < ?`).all(RELEASE_NOTES_VERSION)
  if (!outdated.length) return
  const update = database.prepare(`UPDATE audio_training_published_models
    SET release_summary = ?, release_notes = ?, release_generator_version = ?
    WHERE model_id = ? AND release_generator_version < ?`)
  database.exec('BEGIN IMMEDIATE')
  try {
    for (const row of outdated) {
      // Older releases did not retain a comparison model. Describe their own
      // capabilities without inventing a historical improvement or a new release.
      const release = generateReleaseNotes(hydrateModel(row))
      update.run(release.summary, release.notes, RELEASE_NOTES_VERSION, row.id, RELEASE_NOTES_VERSION)
    }
    database.exec('COMMIT')
  } catch (error) {
    database.exec('ROLLBACK')
    throw error
  }
}

function hydrateModelRelease(row) {
  if (!row?.published_at) return null
  const notes = row.release_notes || ''
  return {
    publishedAt: row.published_at, summary: row.release_summary || '', notes,
    generatedAutomatically: row.release_generator_version === RELEASE_NOTES_VERSION,
    changelog: notes
  }
}

function modelDownloadFileName(createdAt, version) {
  const family = String(version).startsWith('mono-resonance-s1-') ? 'S1' : 'S2'
  const date = new Date(createdAt)
  if (!Number.isFinite(date.getTime())) return `Mono-Resonance-${family}.mlmodel`
  const timestamp = date.toISOString().replace('T', '_').replace(/:/g, '-').replace('Z', 'UTC')
  return `Mono-Resonance-${family}_${timestamp}.mlmodel`
}

function hydrateModel(row) {
  if (!row) return null
  return {
    id: row.id,
    version: row.version,
    featureSchemaVersion: Number(row.feature_schema_version),
    targetSchemaVersion: Number(row.target_schema_version),
    metrics: parseJSON(row.metrics_json, {}),
    datasetFingerprint: row.dataset_fingerprint,
    sampleCount: Number(row.sample_count),
    createdBy: row.created_by || null,
    createdAt: row.created_at
  }
}

function settingsFromJob(row) {
  return normalizeSettings(parseJSON(row?.settings_json, {}))
}

function splitExamples(examples, validationPercent) {
  const complete = examples.filter((item) => item.x !== null)
  const legacy = examples.filter((item) => item.x === null)
  const candidates = complete.length > 0 ? complete : legacy
  const alwaysTraining = complete.length > 0 ? legacy : []
  const groups = new Map()
  for (const item of candidates) {
    const key = item.trackGroup || `proposal:${item.id}`
    const values = groups.get(key) || []
    values.push(item)
    groups.set(key, values)
  }
  const orderedGroups = [...groups.entries()].sort((left, right) => {
    const leftHash = stableBucket(left[0])
    const rightHash = stableBucket(right[0])
    return leftHash === rightHash ? left[0].localeCompare(right[0]) : leftHash - rightHash
  })
  if (orderedGroups.length < 2) {
    return { training: [...candidates, ...alwaysTraining], validation: [] }
  }

  const remainingBranchCounts = new Map()
  for (const item of candidates) {
    const branch = trainingBranchKey(item)
    remainingBranchCounts.set(branch, (remainingBranchCounts.get(branch) || 0) + 1)
  }
  const validationGroupTarget = Math.max(
    1,
    Math.min(
      orderedGroups.length - 1,
      Math.round(orderedGroups.length * validationPercent / 100)
    )
  )
  const validationGroups = new Set()
  for (const [groupKey, values] of orderedGroups) {
    if (validationGroups.size >= validationGroupTarget) break
    const groupBranchCounts = new Map()
    for (const item of values) {
      const branch = trainingBranchKey(item)
      groupBranchCounts.set(branch, (groupBranchCounts.get(branch) || 0) + 1)
    }
    const preservesEveryObservedBranch = [...groupBranchCounts].every(
      ([branch, count]) => (remainingBranchCounts.get(branch) || 0) - count > 0
    )
    if (!preservesEveryObservedBranch) continue
    validationGroups.add(groupKey)
    for (const [branch, count] of groupBranchCounts) {
      remainingBranchCounts.set(branch, remainingBranchCounts.get(branch) - count)
    }
  }
  return {
    training: [
      ...candidates.filter(
        (item) => !validationGroups.has(item.trackGroup || `proposal:${item.id}`)
      ),
      ...alwaysTraining
    ],
    validation: candidates.filter(
      (item) => validationGroups.has(item.trackGroup || `proposal:${item.id}`)
    )
  }
}


function calibrationTrackKey(item) {
  return item.trackGroup || `proposal:${item.id}`
}

// Reserve complete recordings before optimisation. The configured held-out share
// is split between model selection and calibration; neither side trains weights.
function splitCalibrationExamples(examples, validationPercent) {
  // Unidentified recordings cannot be safely separated from held-out songs.
  // Omit them from fitting rather than invalidate all otherwise valid branches.
  const identified = examples.filter(item => item.trackGroup && !item.trackGroup.startsWith('proposal:'))
  const split = splitExamples(identified, validationPercent)
  const groups = [...new Set(split.validation.map(calibrationTrackKey))]
    .sort((a, b) => stableBucket(`calibration:${a}`) - stableBucket(`calibration:${b}`) || a.localeCompare(b))
  const calibrationGroups = new Set(groups.slice(0, Math.floor(groups.length / 2)))
  const heldOutGroups = new Set(groups)
  return {
    excludedUnresolvedTrackSamples: examples.length - identified.length,
    // An older proposal for the same recording must not leak into the prior.
    training: split.training.filter(item => !heldOutGroups.has(calibrationTrackKey(item))),
    validation: split.validation.filter(item => !calibrationGroups.has(calibrationTrackKey(item))),
    calibration: split.validation.filter(item => item.x !== null && calibrationGroups.has(calibrationTrackKey(item)))
  }
}

function assertCalibrationIsolation(training, validation, calibration) {
  const fitted = new Set([...training, ...validation].map(calibrationTrackKey))
  if (calibration.some(item => fitted.has(calibrationTrackKey(item)))) {
    throw trainingError('CALIBRATION_DATA_LEAKAGE', '校准歌曲与训练或选模数据重叠，请重新划分数据。', 422)
  }
}

// Split-conformal simultaneous EQ bands. One recording contributes its maximum
// error across bands and paired contexts, never multiple independent votes.
// Coverage is marginal for exchangeable recordings within this branch, relative
// to the reference EQ target; it is not a probability of subjective sound quality.
function calibrateConfidence({ training, validation, calibration, parameters, prepared }) {
  assertCalibrationIsolation(training, validation, calibration)
  const unresolvedTrackSamples = [...training, ...validation, ...calibration].filter(
    item => !item.trackGroup || item.trackGroup.startsWith('proposal:')
  ).length
  const unresolvedFitSamples = [...training, ...validation].filter(
    item => !item.trackGroup || item.trackGroup.startsWith('proposal:')
  ).length
  const completeFit = [...training, ...validation].filter(item => item.x !== null)
  const branches = Object.fromEntries(ALL_TRAINING_BRANCHES.map(branch => {
    const fitted = completeFit.filter(item => trainingBranchKey(item) === branch)
    const accounts = new Set(fitted.map(item => item.accountId)).size
    const strength = Math.min(1, fitted.length / 64) * (accounts < 2 ? 0.6 : accounts === 2 ? 0.8 : 1)
    const items = calibration.filter(item => item.x !== null && trainingBranchKey(item) === branch)
    const unresolvedBranchSamples = unresolvedFitSamples + items.filter(
      item => !item.trackGroup || item.trackGroup.startsWith('proposal:')
    ).length
    const trackErrors = new Map()
    for (const original of items) {
      for (const item of original.populationPair
        ? [original, { ...original, ...original.populationPair }] : [original]) {
        const prediction = forward(parameters, normalizeVector(item.x, prepared.inputNormalization)).prediction
        const prior = forward(parameters, legacyConditioningVector(item, prepared.inputNormalization)).prediction
        const start = item.graphicEQMode === 'thirtyTwoBand' ? 10 : 0
        const count = item.graphicEQMode === 'thirtyTwoBand' ? 32 : 10
        let error = 0
        for (let i = start; i < start + count; i += 1) {
          if (!item.targetMask[i]) throw trainingError('INVALID_CALIBRATION_TARGET', '校准样本缺少完整 EQ 目标。', 422)
          const raw = (prior[i] + (prediction[i] - prior[i]) * strength)
            * prepared.outputNormalization.standardDeviation[i] + prepared.outputNormalization.mean[i]
          const delta = Math.abs(Math.max(-9, Math.min(9, raw)) - item.y[i])
          if (!Number.isFinite(delta)) throw trainingError('INVALID_CALIBRATION_TARGET', '校准样本包含无效数值。', 422)
          error = Math.max(error, delta)
        }
        const key = calibrationTrackKey(original)
        trackErrors.set(key, Math.max(trackErrors.get(key) || 0, error))
      }
    }
    const scores = [...trackErrors.values()].sort((a, b) => a - b)
    const rank = Math.ceil((scores.length + 1) * CALIBRATION_COVERAGE)
    const ready = unresolvedBranchSamples === 0 && scores.length >= MINIMUM_CALIBRATION_TRACKS && rank <= scores.length
    return [branch, {
      status: ready ? 'calibrated' : unresolvedBranchSamples > 0
        ? 'unresolved_track_identity' : 'insufficient_calibration_tracks',
      unresolvedTrackSamples: unresolvedBranchSamples,
      samples: items.length, tracks: scores.length, quantileRank: rank,
      // Core ML uses float32; reserve the native parity tolerance in dB.
      radiusDB: ready ? scores[rank - 1] + CALIBRATION_NUMERICAL_MARGIN_DB : null,
      trackCorrectionStrength: strength
    }]
  }))
  return {
    schemaVersion: 1, method: CALIBRATION_METHOD, scope: 'graphic-eq-reference',
    unresolvedTrackSamples,
    coverage: CALIBRATION_COVERAGE, minimumTracks: MINIMUM_CALIBRATION_TRACKS,
    numericalMarginDB: CALIBRATION_NUMERICAL_MARGIN_DB,
    trainingTracks: new Set(training.map(calibrationTrackKey)).size,
    selectionTracks: new Set(validation.map(calibrationTrackKey)).size,
    calibrationTracks: new Set(calibration.map(calibrationTrackKey)).size,
    branches
  }
}


function featureBranch(name) {
  if (name.startsWith('tenBand.')) return 'tenBand'
  if (name.startsWith('thirtyTwoBand.')) return 'thirtyTwoBand'
  return null
}

// Features of the same physical kind share statistics when one band branch has
// too few samples: `tenBand.bandEnergyDB.3` and `thirtyTwoBand.bandEnergyDB.17`
// are both dB energies and should be scaled alike.
function featureFamily(name) {
  return name
    .replace(/^(tenBand|thirtyTwoBand)\./, '')
    .replace(/(\.\d+)+$/, '')
}

// Features that are structurally zero when their context is absent (inactive
// band branch, no learning state, no detailed device, no vocal reference) must
// keep zero at zero after normalisation. Centering them would turn every
// absent context into a large constant that saturates the hidden layer.
const CONDITIONAL_FEATURE_PREFIXES = ['tenBand.', 'thirtyTwoBand.', 'learning.', 'device.', 'vocalReference.']

// One-hot, boolean and [0, 1] confidence inputs are already on a unit scale.
// They are passed through raw so a category never seen in training still maps
// to 1, not to the clip boundary.
const UNIT_SCALE_FEATURE_PREFIXES = [
  'genreHint.', 'instrumentHint.', 'genreScore.', 'instrumentScore.', 'outputKind.',
  'tuningIntensity.', 'tuningProfile.', 'device.profileSource.', 'chroma.'
]
const UNIT_SCALE_FEATURE_NAMES = new Set([
  ...booleanFeatureNames,
  'graphicEQMode.thirtyTwoBand',
  'learning.active', 'learning.confidence',
  'device.detailActive', 'device.calibrationEnabled', 'device.profileActive', 'device.profileIsCustom'
])

function isUnitScaleFeature(name) {
  if (UNIT_SCALE_FEATURE_NAMES.has(name)) return true
  if (UNIT_SCALE_FEATURE_PREFIXES.some((prefix) => name.startsWith(prefix))) return true
  return /^device\.filter\.\d+\.(active|kind\.)/.test(name)
}

function isConditionalFeature(name) {
  return CONDITIONAL_FEATURE_PREFIXES.some((prefix) => name.startsWith(prefix))
}

function defaultFeatureScale(name) {
  if (/(Hz|SampleRate)$/i.test(name)) return 10_000
  if (/(DB|DBFS|DBTP|LUFS|LU|Gain|Adjustment)$/i.test(name) || /GainsDB\.\d+$|EnergyDB\.\d+$|SpreadDB\.\d+$/.test(name)) return 12
  if (/(MS)$/.test(name)) return 100
  if (/Count$/.test(name)) return 8
  return 1
}

function rootMeanSquare(values) {
  let sum = 0
  for (const value of values) sum += value * value
  return Math.sqrt(sum / Math.max(1, values.length))
}

// Input statistics come from complete samples only (legacy plans carry no
// measurements). Binary features stay raw 0/1. Conditional features are
// scale-only (mean 0) using the RMS of their observed non-zero values, borrowing
// their feature family (e.g. all `bandEnergyDB` bands of either branch) when
// their own branch is under-sampled, and falling back to a physical default
// scale when nothing was observed. Unconditional measurements are centred with
// a floor on sigma so a feature constant in a small dataset cannot explode.
function normalization(examples) {
  const width = featureNames.length
  const mean = Array(width).fill(0)
  const standardDeviation = Array(width).fill(1)
  if (!examples.length) return { mean, standardDeviation }
  const familyValues = new Map()
  const observed = featureNames.map((name, index) => {
    const all = examples.map((example) => example.x[index])
    const nonZero = all.filter((value) => value !== 0)
    if (isConditionalFeature(name)) {
      const family = featureFamily(name)
      const pooled = familyValues.get(family) || []
      pooled.push(...nonZero)
      familyValues.set(family, pooled)
    }
    return { name, all, nonZero }
  })
    for (let index = 0; index < width; index += 1) {
    const { name, all, nonZero } = observed[index]
    if (isUnitScaleFeature(name)) {
      mean[index] = 0
      standardDeviation[index] = 1
      continue
    }
    if (isConditionalFeature(name)) {
      let source = nonZero
      if (source.length < MINIMUM_NORMALIZATION_SAMPLES) {
        const pooled = familyValues.get(featureFamily(name)) || []
        if (pooled.length > source.length) source = pooled
      }
      mean[index] = 0
      standardDeviation[index] = source.length
        ? Math.max(0.05, rootMeanSquare(source))
        : defaultFeatureScale(name)
      continue
    }
    const average = all.reduce((sum, value) => sum + value, 0) / all.length
    let variance = 0
    for (const value of all) variance += (value - average) ** 2
    const std = Math.sqrt(variance / all.length)
    mean[index] = average
    standardDeviation[index] = Math.max(std, 0.05, 0.05 * Math.abs(average))
  }
  return { mean, standardDeviation }
}

// Targets retain their absolute zero so a legacy-only dataset must genuinely
// optimize the output bias. Centering them around their own mean would make
// the initial zero bias an already-solved model and produce no training step.
function outputScaling(vectors, masks = [], widthHint = 0) {
  const width = vectors[0]?.length || widthHint
  const mean = Array(width).fill(0)
  const sumOfSquares = Array(width).fill(0)
  const counts = Array(width).fill(0)
  for (const [vectorIndex, vector] of vectors.entries()) {
    const mask = masks[vectorIndex] || Array(width).fill(1)
    for (let index = 0; index < width; index += 1) {
      if (mask[index] === 0) continue
      sumOfSquares[index] += vector[index] * vector[index]
      counts[index] += 1
    }
  }
  const standardDeviation = Array(width).fill(0)
  for (let index = 0; index < width; index += 1) {
    // Never-observed or all-zero targets keep a unit scale so predictions for
    // them stay in raw units instead of being amplified a thousandfold.
    standardDeviation[index] = counts[index] === 0
      ? 1
      : Math.max(0.05, Math.sqrt(sumOfSquares[index] / counts[index]))
  }
  return { mean, standardDeviation }
}

function normalizeVector(vector, statistics) {
  return vector.map((value, index) =>
    clamp((value - statistics.mean[index]) / statistics.standardDeviation[index], -8, 8))
}

function resample(raw, count) {
  const values = Array.isArray(raw) ? raw.map((value) => finite(value)) : []
  if (values.length === 0) return Array(count).fill(0)
  if (values.length === count) return values
  if (values.length === 1) return Array(count).fill(values[0])
  return Array.from({ length: count }, (_, index) => {
    const position = (index * (values.length - 1)) / Math.max(1, count - 1)
    const lower = Math.floor(position)
    const upper = Math.min(values.length - 1, lower + 1)
    const fraction = position - lower
    return values[lower] + (values[upper] - values[lower]) * fraction
  })
}

function modeBandBranches(mode, raw) {
  return mode === 'thirtyTwoBand'
    ? [...Array(10).fill(0), ...resample(raw, 32)]
    : [...resample(raw, 10), ...Array(32).fill(0)]
}

function modeSectionBranches(mode, activeSections) {
  const active = activeSections.flat()
  return mode === 'thirtyTwoBand'
    ? [...Array(TRACK_SECTION_COUNT * 10).fill(0), ...active]
    : [...active, ...Array(TRACK_SECTION_COUNT * 32).fill(0)]
}

function fixedArray(raw, count) {
  const values = Array.isArray(raw) ? raw.slice(0, count).map((value) => finite(value)) : []
  while (values.length < count) values.push(0)
  return values
}

function confidenceVector(rawScores, rawHints, values) {
  const scores = rawScores && typeof rawScores === 'object' && !Array.isArray(rawScores)
    ? rawScores
    : null
  if (!scores) return multiHotVector(rawHints, values)
  return values.map((value) => clamp(finite(scores[value]), 0, 1))
}

function fixedSectionProfiles(rawSections, fallbackBands, bandCount = TRACK_BAND_COUNT) {
  const sections = Array.isArray(rawSections) ? rawSections.slice(0, TRACK_SECTION_COUNT) : []
  const fallback = resample(fallbackBands, bandCount)
  const result = sections.map((section) => resample(section, bandCount))
  while (result.length < TRACK_SECTION_COUNT) result.push([...fallback])
  return result
}

function hasTemporalTrackEvidence(features) {
  return Array.isArray(features?.bandEnergySpreadDB)
    && features.bandEnergySpreadDB.length > 0
    && Array.isArray(features?.sectionBandEnergyDB)
    && features.sectionBandEnergyDB.length > 1
}

function isActiveLearningContext(value) {
  return value && typeof value === 'object' && !Array.isArray(value)
    && finite(value.evidenceCount) > 0
    && finite(value.confidence) >= 0.04
}

function learningContextVector(value, mode = 'tenBand') {
  return [
    1,
    clamp(finite(value?.confidence), 0, 1),
    clamp(finite(value?.evidenceCount), 0, 10_000),
    ...modeBandBranches(mode, value?.bandAdjustments || []),
    finite(value?.bassAdjustment),
    finite(value?.trebleAdjustment),
    finite(value?.surroundAdjustment),
    finite(value?.reverbAdjustment),
    finite(value?.stereoWidthAdjustment),
    finite(value?.processingIntensityAdjustment)
  ]
}

function isDetailedDeviceContext(value) {
  return value && typeof value === 'object' && !Array.isArray(value)
    && Number(value.detailSchemaVersion) >= 1
    && Array.isArray(value.effectiveGainsDB)
    && value.effectiveGainsDB.length > 0
}

function deviceContextVector(value) {
  const rawFilters = Array.isArray(value?.acousticFilters)
    ? value.acousticFilters.slice(0, DEVICE_FILTER_SLOT_COUNT)
    : []
  const filters = Array.from({ length: DEVICE_FILTER_SLOT_COUNT }, (_, slot) => {
    const filter = rawFilters[slot]
    if (!filter || typeof filter !== 'object' || Array.isArray(filter)) {
      return Array(1 + deviceFilterKindFeatureValues.length + 4).fill(0)
    }
    return [
      1,
      ...oneHotVector(filter.kind, deviceFilterKindFeatureValues, ''),
      clamp(finite(filter.frequencyHz), 10, 96_000),
      clamp(finite(filter.gainDB), -24, 24),
      clamp(finite(filter.q), 0.05, 100),
      clamp(finite(filter.slopeDBPerOctave), 0, 96)
    ]
  }).flat()
  return [
    1,
    value?.calibrationEnabled === true ? 1 : 0,
    value?.profileActive === true ? 1 : 0,
    value?.profileIsCustom === true ? 1 : 0,
    clamp(finite(value?.outputSampleRate), 8_000, 384_000),
    clamp(finite(value?.outputChannelCount), 1, 32),
    clamp(finite(value?.outputLatencyMS), 0, 5_000),
    clamp(finite(value?.ioBufferDurationMS), 0, 1_000),
    clamp(finite(value?.profilePreampDB), -18, 0),
    clamp(finite(rawFilters.length), 0, DEVICE_FILTER_SLOT_COUNT),
    ...oneHotVector(value?.profileSource, deviceProfileSourceFeatureValues, 'none'),
    ...resample(value?.routeDefaultGainsDB || [], TRACK_BAND_COUNT)
      .map((item) => clamp(item, -18, 18)),
    ...resample(value?.profileGainsDB || [], DEVICE_CURVE_BAND_COUNT)
      .map((item) => clamp(item, -18, 18)),
    ...resample(value?.effectiveGainsDB || [], DEVICE_CURVE_BAND_COUNT)
      .map((item) => clamp(item, -18, 18)),
    ...filters
  ]
}

function trainingOutcomeWeight(sample, manualCorrected = false) {
  switch (String(sample?.feedback || '')) {
  case 'positive': return 1.25
  case 'retained': return 1
  // Without the listener's final curve a manual edit only tells us the
  // proposal was not what they wanted; it must not be the strongest label.
  case 'manualEqualizer': return manualCorrected ? 1.35 : 0.45
  case 'negative':
  case 'reset':
  case 'regenerated': return 0
  default: return 0.45
  }
}

function proposalTuningIntensity(proposal) {
  const value = String(proposal?.tuningIntensity || '')
  return tuningIntensityFeatureValues.includes(value) ? value : 'smart'
}

function trainingGroupKey(songIdentifier, proposalId) {
  const value = String(songIdentifier || '').trim().toLowerCase()
  return value ? `track:${value}` : `proposal:${String(proposalId || '').toLowerCase()}`
}

function stableBucket(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest().readUInt32BE(0)
}

function multiHotVector(raw, values) {
  const selected = new Set(
    (Array.isArray(raw) ? raw : [])
      .map((value) => String(value || '').trim().toLowerCase())
      .filter(Boolean)
  )
  return values.map((value) => selected.has(value.toLowerCase()) ? 1 : 0)
}

function oneHotVector(raw, values, fallback) {
  const candidate = String(raw || '').trim()
  const selected = values.includes(candidate) ? candidate : fallback
  return values.map((value) => value === selected ? 1 : 0)
}

function finite(value, fallback = 0) {
  const number = Number(value)
  return Number.isFinite(number) ? number : fallback
}

function finiteOrNull(value) {
  return value === null || value === undefined ? null : (Number.isFinite(Number(value)) ? Number(value) : null)
}

function integer(value, minimum, maximum, fallback = minimum) {
  const number = Number(value)
  return Number.isFinite(number)
    ? Math.min(maximum, Math.max(minimum, Math.round(number)))
    : fallback
}

function clamp(value, minimum, maximum) {
  return Math.min(maximum, Math.max(minimum, value))
}

function dot(left, right) {
  let result = 0
  for (let index = 0; index < left.length; index += 1) result += left[index] * right[index]
  return result
}

function deterministicShuffle(values, random) {
  for (let index = values.length - 1; index > 0; index -= 1) {
    const other = Math.floor(random() * (index + 1))
    const current = values[index]
    values[index] = values[other]
    values[other] = current
  }
}

function seededRandom(seed) {
  let state = seed >>> 0
  return () => {
    state = (Math.imul(1664525, state) + 1013904223) >>> 0
    return state / 0x100000000
  }
}

function ensureNotCancelled(run) {
  if (run?.cancelled) throw trainingError('TRAINING_CANCELLED', '训练已取消。', 409)
}

function immediate() {
  return new Promise((resolve) => setImmediate(resolve))
}

function parseJSON(value, fallback) {
  try { return JSON.parse(value) } catch (_) { return fallback }
}

function normalizedProposalId(value) {
  const id = String(value?.id || value?.proposal?.id || '').trim().toLowerCase()
  return id || null
}

function proposalGraphicEQMode(proposal) {
  return proposal?.graphicEQMode === 'thirtyTwoBand'
    || (Array.isArray(proposal?.gains) && proposal.gains.length === 32)
    ? 'thirtyTwoBand'
    : 'tenBand'
}

function proposalTuningProfile(proposal) {
  return proposal?.tuningProfile === 'monoSpatialEnhancement'
    ? 'monoSpatialEnhancement'
    : 'standard'
}

function sampleGraphicEQMode(sample) {
  return sample?.features?.graphicEQMode === 'thirtyTwoBand'
    ? 'thirtyTwoBand'
    : 'tenBand'
}

function cleanActor(value) {
  const text = String(value || '').trim()
  return text ? text.slice(0, 160) : null
}

function actor(req) {
  return cleanActor(req.admin?.id || req.user?.id || req.auth?.id || 'token-admin')
}

function trainingError(code, message, statusCode) {
  const error = new Error(message)
  error.code = code
  error.statusCode = statusCode
  return error
}

function route(handler, logger) {
  return (req, res) => Promise.resolve(handler(req, res)).catch((error) => {
    logger.error('[audio-training] Request failed:', error)
    res.status(error.statusCode || 500).json({
      ok: false,
      code: error.code || 'AUDIO_TRAINING_FAILED',
      error: error.message || '音频模型训练失败。'
    })
  })
}

// Worker bootstrap must follow every module-level declaration it depends on.
if (!isMainThread && workerData?.audioTuningTrainer) {
  try {
    const { training, validation, calibration, settings, cancelFlag } = workerData
    const result = trainTinyModelSync({
      training,
      validation,
      calibration,
      settings,
      progress: (event) => {
        parentPort.postMessage({ type: 'epoch', ...event })
        return Atomics.load(cancelFlag, 0) === 0
      }
    })
    parentPort.postMessage({ type: 'done', result })
  } catch (error) {
    parentPort.postMessage({
      type: 'error',
      message: error?.message || '训练失败。',
      code: error?.code,
      statusCode: error?.statusCode
    })
  }
}

module.exports = {
  FEATURE_SCHEMA_VERSION,
  MODEL_FAMILY,
  MODEL_NAME,
  MODEL_VERSION_PREFIX,
  MODEL_ARCHITECTURE,
  TARGET_SCHEMA_VERSION,
  collectDataset,
  createAudioTuningTrainingService,
  featureNames,
  installAudioTuningTrainingRoutes,
  isSelfGeneratedProposal,
  normalizeSettings,
  splitExamples,
  splitCalibrationExamples,
  calibrateConfidence,
  targetNames,
  trainTinyModelSync,
  forward,
  initializeParameters,
  zeroLike,
  accumulateGradients,
  targetLossWeights,
  prepareTrainingSet,
  trainingVectors
}
