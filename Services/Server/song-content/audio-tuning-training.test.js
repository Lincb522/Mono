'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const test = require('node:test')

const {
  FEATURE_SCHEMA_VERSION,
  MODEL_FAMILY,
  MODEL_NAME,
  MODEL_VERSION_PREFIX,
  MODEL_ARCHITECTURE,
  collectDataset,
  createAudioTuningTrainingService,
  featureNames,
  installAudioTuningTrainingRoutes,
  isSelfGeneratedProposal,
  normalizeSettings,
  splitExamples,
  targetNames,
  trainTinyModelSync,
  forward,
  initializeParameters,
  zeroLike,
  accumulateGradients,
  targetLossWeights,
  prepareTrainingSet,
  trainingVectors
} = require('./audio-tuning-training')

function proposal(id, mode = 'tenBand') {
  return {
    id,
    graphicEQMode: mode,
    gains: Array.from({ length: mode === 'thirtyTwoBand' ? 32 : 10 }, (_, index) => index * 0.1),
    preampDB: -1,
    tone: { bassGain: 0.2, trebleGain: -0.1 },
    spatial: { surroundLevel: 0.1, reverbLevel: 0.05, stereoWidth: 1.05 },
    enhance: { isEnabled: true, transientAttack: 0.2 },
    calibration: {},
    professional: { processingIntensity: 0.3, dynamicEQ: {}, multiband: {}, parametricEQ: {} },
    effects: { finalLimiterEnabled: true, finalLimiterCeilingDB: -1 },
    tuningIntensity: 'strong',
    tuningProfile: 'monoSpatialEnhancement',
    skillCompliance: { accepted: true, localValidationApplied: true }
  }
}

function sample(id, mode = 'tenBand') {
  return {
    schemaVersion: 4,
    id,
    songIdentifier: `netease:${id}`,
    capturedAt: '2026-09-02T12:00:00.000Z',
    feedback: 'positive',
    features: {
      graphicEQMode: mode,
      bandEnergyDB: Array(mode === 'thirtyTwoBand' ? 32 : 10).fill(-24),
      chroma: Array(12).fill(0.1),
      integratedLUFS: -14,
      phaseCorrelation: 0.8,
      outputKind: 'bluetooth',
      genreHints: ['pop', 'rock'],
      instrumentHints: ['vocals', 'guitar'],
      genreScores: { pop: 0.72, rock: 0.24 },
      instrumentScores: { vocals: 0.81, guitar: 0.43 },
      bandEnergySpreadDB: Array(10).fill(4),
      sectionBandEnergyDB: [
        Array(10).fill(-18),
        Array(10).fill(-12),
        Array(10).fill(-8)
      ],
      spectralCentroidP10Hz: 1200,
      spectralCentroidP90Hz: 3200,
      spectralRolloffP10Hz: 4200,
      spectralRolloffP90Hz: 9200,
      spectralFluxP90: 0.4,
      rmsP10DBFS: -24,
      rmsP50DBFS: -17,
      rmsP90DBFS: -10
    },
    deviceContext: { referenceGainsDB: Array(10).fill(0) },
    target: proposal(id, mode)
  }
}

function detailedDeviceContext({ source = 'opra', gain = 1 } = {}) {
  return {
    detailSchemaVersion: 1,
    identifier: `device:${source}:${gain}`,
    outputKind: 'bluetooth',
    profileSource: source,
    calibrationEnabled: true,
    profileActive: true,
    profileIsCustom: source === 'custom',
    outputSampleRate: 48_000,
    outputChannelCount: 2,
    outputLatencyMS: source === 'opra' ? 145 : 32,
    ioBufferDurationMS: 5.33,
    routeDefaultGainsDB: Array.from({ length: 10 }, (_, index) => gain * index / 10),
    profileGainsDB: Array.from({ length: 32 }, (_, index) => gain * Math.sin(index / 4)),
    referenceGainsDB: Array(10).fill(0),
    effectiveGainsDB: Array.from({ length: 32 }, (_, index) => gain * Math.cos(index / 5)),
    profilePreampDB: gain > 0 ? -4 : -1,
    acousticFilters: [
      {
        kind: 'peak_dip',
        frequencyHz: gain > 0 ? 240 : 3_200,
        gainDB: gain * 2.5,
        q: gain > 0 ? 0.8 : 2.4,
        slopeDBPerOctave: 0
      },
      {
        kind: 'high_shelf',
        frequencyHz: 8_000,
        gainDB: -gain,
        q: 0.7,
        slopeDBPerOctave: 12
      }
    ],
    fitDescription: source === 'opra' ? 'sealed reference fit' : 'custom output profile',
    spatialGuidance: 'keep the center stable'
  }
}

function createCloudDatabase(directory, snapshots) {
  const { DatabaseSync } = require('node:sqlite')
  const databasePath = path.join(directory, 'cloud-storage.sqlite')
  const database = new DatabaseSync(databasePath)
  database.exec('CREATE TABLE cloud_snapshots (token_id TEXT PRIMARY KEY, snapshot_json TEXT NOT NULL)')
  const insert = database.prepare('INSERT INTO cloud_snapshots (token_id, snapshot_json) VALUES (?, ?)')
  snapshots.forEach((snapshot, index) => insert.run(`account-${index}`, JSON.stringify(snapshot)))
  database.close()
  return databasePath
}

function branchCoverageSnapshots(prefix) {
  return [
    ['tenBand', 'standard'],
    ['tenBand', 'monoSpatialEnhancement'],
    ['thirtyTwoBand', 'standard'],
    ['thirtyTwoBand', 'monoSpatialEnhancement']
  ].map(([mode, profile], index) => {
    const id = `${prefix}-coverage-${index}`
    const target = proposal(id, mode)
    target.tuningProfile = profile
    const isSpatial = profile === 'monoSpatialEnhancement'
    target.spatial = isSpatial
      ? { surroundLevel: 0.55, reverbLevel: 0.3, stereoWidth: 1.42 }
      : { surroundLevel: 0.02, reverbLevel: 0.01, stereoWidth: 1.02 }
    target.enhance.stageWidth = isSpatial ? 0.68 : 0.06
    return {
      aiEqualizer: {
        cachedProposals: {},
        savedProposals: { [id]: [{ id, proposal: target }] }
      }
    }
  })
}

function createCoveredCloudDatabase(directory, snapshots, prefix) {
  return createCloudDatabase(directory, [
    ...snapshots,
    ...branchCoverageSnapshots(prefix)
  ])
}

async function fakeCoreMLExporter({ sourcePath, outputPath }) {
  const source = JSON.parse(fs.readFileSync(sourcePath, 'utf8'))
  assert.equal(source.featureSchemaVersion, FEATURE_SCHEMA_VERSION)
  assert.deepEqual(source.artifact.featureNames, featureNames)
  assert.deepEqual(source.artifact.targetNames, targetNames)
  fs.writeFileSync(outputPath, Buffer.alloc(512, 0x4d))
}

function artifactPrediction(artifact, input) {
  const normalized = input.map((value, index) => Math.min(8, Math.max(
    -8,
    (value - artifact.inputNormalization.mean[index])
      / artifact.inputNormalization.standardDeviation[index]
  )))
  return forward(artifact, normalized).prediction.map((value, outputIndex) => {
    return value * artifact.outputNormalization.standardDeviation[outputIndex]
      + artifact.outputNormalization.mean[outputIndex]
  })
}

test('complete samples produce fixed trainable vectors', () => {
  const value = sample('sample-1')
  value.deviceContext.referenceGainsDB = Array(10).fill(0.25)
  const vector = trainingVectors(value)
  assert.ok(vector)
  assert.equal(vector.x.length, featureNames.length)
  assert.equal(vector.y.length, targetNames.length)
  assert.ok(vector.x.every(Number.isFinite))
  assert.ok(vector.y.every(Number.isFinite))
  assert.equal(vector.y[0], -0.25)
  assert.equal(vector.y[9], 0.65)
  assert.equal(FEATURE_SCHEMA_VERSION, 7)
  assert.equal(vector.x.length, 636)
  assert.equal(vector.x[featureNames.indexOf('genreScore.pop')], 0.72)
  assert.equal(vector.x[featureNames.indexOf('genreScore.rock')], 0.24)
  assert.equal(vector.x[featureNames.indexOf('genreScore.ballad')], 0)
  assert.equal(vector.x[featureNames.indexOf('instrumentScore.vocals')], 0.81)
  assert.equal(vector.x[featureNames.indexOf('instrumentScore.guitar')], 0.43)
  assert.equal(vector.x[featureNames.indexOf('outputKind.bluetooth')], 1)
  assert.equal(vector.x[featureNames.indexOf('tuningIntensity.strong')], 1)
  assert.equal(vector.x[featureNames.indexOf('tuningProfile.monoSpatialEnhancement')], 1)
  assert.equal(vector.x[featureNames.indexOf('tuningProfile.standard')], 0)
  assert.equal(vector.tuningProfile, 'monoSpatialEnhancement')
  assert.equal(vector.x[featureNames.indexOf('tenBand.bandEnergySpreadDB.0')], 4)
  assert.equal(vector.x[featureNames.indexOf('tenBand.sectionBandEnergyDB.1.0')], -12)
  assert.equal(vector.x[featureNames.indexOf('spectralCentroidP90Hz')], 3200)
  assert.equal(vector.x[featureNames.indexOf('learning.active')], 0)
  assert.equal(vector.x[featureNames.indexOf('device.detailActive')], 0)
  assert.equal(vector.temporallyConditioned, true)
})

test('residual and nonlinear intent gradients match finite differences with native target masks', () => {
  for (const intentUnits of [0, 3]) {
    let seed = 137
    const random = () => ((seed = (1664525 * seed + 1013904223) >>> 0) / 2 ** 32)
    const parameters = initializeParameters(normalizeSettings({ hiddenUnits: 4, intentUnits }), random)
    const targetMask = targetNames.map((_, index) => index < 10 || index === 42 ? 1 : 0)
    const item = {
      x: featureNames.map((_, index) => index < 8 ? random() - 0.5 : 0),
      y: targetNames.map(() => random() - 0.5),
      targetMask, lossWeights: targetLossWeights(targetMask), sampleWeight: 0.7
    }
    const gradients = zeroLike(parameters)
    accumulateGradients(parameters, gradients, item, 2)
    const objective = () => forward(parameters, item.x).prediction.reduce((sum, value, index) =>
      sum + item.lossWeights[index] * (value - item.y[index]) ** 2 * item.sampleWeight / 2, 0)
    for (const key of Object.keys(parameters)) {
      if (!parameters[key]) continue
      const isMatrix = Array.isArray(parameters[key][0])
      const row = isMatrix ? parameters[key][0] : parameters[key]
      const analytic = isMatrix ? gradients[key][0][0] : gradients[key][0]
      const original = row[0]
      row[0] = original + 1e-5
      const plus = objective()
      row[0] = original - 1e-5
      const minus = objective()
      row[0] = original
      const numerical = (plus - minus) / 2e-5
      assert.ok(Math.abs(analytic - numerical) < 1e-6, `${intentUnits}/${key}: ${analytic} vs ${numerical}`)
    }
    assert.ok(gradients.outputHeadWeights[10].every((value) => value === 0))
    if (intentUnits) assert.ok(gradients.outputSkipWeights[10].every((value) => value === 0))
  }
})

test('target families receive equal loss mass and masked detailed slots stay inactive', () => {
  const mask = targetNames.map((name) => /^(tenBand|professional.parametricEQ)/.test(name) ? 1 : 0)
  const weights = targetLossWeights(mask)
  const eqMass = weights.slice(0, 10).reduce((sum, value) => sum + value, 0)
  const peqMass = weights.reduce((sum, value, index) =>
    sum + (targetNames[index].startsWith('professional.parametricEQ') ? value : 0), 0)
  assert.ok(Math.abs(eqMass - peqMass) < 1e-9)
  assert.ok(weights.slice(10, 42).every((value) => value === 0))
  assert.deepEqual(targetLossWeights(Array(targetNames.length).fill(0)), Array(targetNames.length).fill(0))
})

test('missing held-out tracks do not report training loss as validation evidence', () => {
  const value = sample('no-validation')
  const trained = trainTinyModelSync({
    training: [{ ...trainingVectors(value), id: value.id, trackGroup: 'one-track', accountId: 'one-account' }],
    validation: [], settings: normalizeSettings({ epochs: 1, hiddenUnits: 4, intentUnits: 0 })
  })
  assert.equal(trained.initialValidationLoss, null)
  assert.equal(trained.validationLoss, null)
  assert.equal(trained.selectionSource, 'trainingLoss')
})

test('measured branch balancing reduces population imbalance without fabricating missing branches', () => {
  const training = Array.from({ length: 40 }, (_, index) => {
    const value = sample(`branch-balance-${index}`)
    value.target.tuningProfile = index === 39 ? 'monoSpatialEnhancement' : 'standard'
    return { ...trainingVectors(value), id: value.id, accountId: 'one-account', trackGroup: value.songIdentifier }
  })
  const prepared = prepareTrainingSet({ training, validation: [], settings: normalizeSettings({}) })
  const standardMass = prepared.train.slice(0, 39).reduce((sum, item) => sum + item.sampleWeight, 0)
  const spatialMass = prepared.train[39].sampleWeight
  assert.ok(Math.abs(standardMass / spatialMass - Math.sqrt(39)) < 1e-8)
  assert.equal(prepared.train.length, 40)
  assert.ok(prepared.train.every((item) => item.targetMask.slice(10, 42).every((value) => value === 0)))
})

test('32-band samples preserve native input and target resolution', () => {
  const value = sample('native-32', 'thirtyTwoBand')
  value.features.bandEnergyDB = Array.from({ length: 32 }, (_, index) => -32 + index)
  value.features.bandEnergySpreadDB = Array.from({ length: 32 }, (_, index) => index / 10)
  value.features.sectionBandEnergyDB = Array.from({ length: 3 }, (_, section) =>
    Array.from({ length: 32 }, (_, index) => section * 100 + index))
  value.target.gains = Array.from({ length: 32 }, (_, index) => index / 4)
  const vector = trainingVectors(value)
  assert.ok(vector)
  assert.equal(vector.graphicEQMode, 'thirtyTwoBand')
  assert.equal(vector.x.length, 636)
  assert.equal(vector.y.length, 197)
  assert.equal(vector.x[featureNames.indexOf('thirtyTwoBand.bandEnergyDB.31')], -1)
  assert.equal(vector.x[featureNames.indexOf('tenBand.bandEnergyDB.0')], 0)
  assert.equal(vector.x[featureNames.indexOf('thirtyTwoBand.sectionBandEnergyDB.2.31')], 231)
  assert.equal(vector.y[targetNames.indexOf('thirtyTwoBand.gains.31')], 7.75)
  assert.equal(vector.targetMask[targetNames.indexOf('tenBand.gains.0')], 0)
  assert.equal(vector.targetMask[targetNames.indexOf('thirtyTwoBand.gains.31')], 1)
  assert.equal(vector.targetMask[targetNames.indexOf('preampDB')], 1)
})

test('detailed device parameters are model inputs while the target stays device-free', () => {
  const value = sample('detailed-device')
  value.deviceContext = detailedDeviceContext({ source: 'opra', gain: 1.5 })
  value.populationTarget = proposal('device-free-population')
  value.populationTarget.gains = Array(10).fill(0.75)
  const vector = trainingVectors(value)
  assert.ok(vector)
  assert.equal(vector.deviceConditioned, true)
  assert.equal(vector.x[featureNames.indexOf('device.detailActive')], 1)
  assert.equal(vector.x[featureNames.indexOf('device.profileSource.opra')], 1)
  assert.equal(vector.x[featureNames.indexOf('device.outputSampleRate')], 48_000)
  assert.equal(vector.x[featureNames.indexOf('device.outputChannelCount')], 2)
  assert.equal(vector.x[featureNames.indexOf('device.filter.0.active')], 1)
  assert.equal(vector.x[featureNames.indexOf('device.filter.0.kind.peak_dip')], 1)
  assert.equal(vector.x[featureNames.indexOf('device.filter.0.frequencyHz')], 240)
  assert.equal(vector.x[featureNames.indexOf('device.filter.1.kind.high_shelf')], 1)
  assert.deepEqual(vector.y.slice(0, 10), Array(10).fill(0.75))
})

test('legacy complete samples remain trainable with derived style and temporal fallbacks', () => {
  const value = sample('legacy-complete')
  value.schemaVersion = 1
  delete value.features.genreScores
  delete value.features.instrumentScores
  delete value.features.bandEnergySpreadDB
  delete value.features.sectionBandEnergyDB
  const vector = trainingVectors(value)
  assert.ok(vector)
  assert.equal(vector.x[featureNames.indexOf('genreScore.pop')], 1)
  assert.equal(vector.x[featureNames.indexOf('instrumentScore.vocals')], 1)
  assert.equal(vector.x[featureNames.indexOf('tenBand.sectionBandEnergyDB.0.0')], -24)
  assert.equal(vector.temporallyConditioned, false)
})

test('training outcome weights prefer confirmed listening and exclude rejected proposals', () => {
  const unverified = sample('unverified')
  delete unverified.feedback
  const retained = sample('retained')
  retained.feedback = 'retained'
  const rejected = sample('rejected')
  rejected.feedback = 'negative'
  assert.equal(trainingVectors(unverified).sampleWeight, 0.45)
  assert.equal(trainingVectors(retained).sampleWeight, 1)
  assert.equal(trainingVectors(rejected).sampleWeight, 0)
})

test('population target is not contaminated by device correction', () => {
  const value = sample('population-target')
  value.deviceContext.referenceGainsDB = Array(10).fill(2)
  value.populationTarget = proposal('population-base')
  value.populationTarget.gains = Array(10).fill(1.5)
  const vector = trainingVectors(value)
  assert.ok(vector)
  assert.deepEqual(vector.y.slice(0, 10), Array(10).fill(1.5))
})

test('agent learning context uses a personalized target without device correction', () => {
  const value = sample('learning-target')
  value.deviceContext.referenceGainsDB = Array(10).fill(3)
  value.learningContext = {
    revision: 12,
    evidenceCount: 8,
    confidence: 0.32,
    bandAdjustments: Array.from({ length: 10 }, (_, index) => index * 0.1),
    bassAdjustment: 0.4,
    trebleAdjustment: -0.2,
    surroundAdjustment: 0.03,
    reverbAdjustment: -0.01,
    stereoWidthAdjustment: 0.02,
    processingIntensityAdjustment: 0.06
  }
  value.populationTarget = proposal('population-base')
  value.populationTarget.gains = Array(10).fill(-1)
  value.personalizedTarget = proposal('personalized-base')
  value.personalizedTarget.gains = Array(10).fill(2.5)

  const vector = trainingVectors(value, { targetMode: 'personalized' })
  assert.ok(vector)
  assert.equal(vector.learningConditioned, true)
  assert.equal(vector.x[featureNames.indexOf('learning.active')], 1)
  assert.equal(vector.x[featureNames.indexOf('learning.confidence')], 0.32)
  assert.equal(vector.x[featureNames.indexOf('learning.evidenceCount')], 8)
  assert.equal(vector.x[featureNames.indexOf('tenBand.learning.bandAdjustments.9')], 0.9)
  assert.equal(vector.x[featureNames.indexOf('learning.bassAdjustment')], 0.4)
  assert.deepEqual(vector.y.slice(0, 10), Array(10).fill(2.5))
})

test('population target mode ignores private learning context and personalized targets', () => {
  const value = sample('population-mode')
  value.deviceContext.referenceGainsDB = Array(10).fill(3)
  value.learningContext = {
    revision: 12,
    evidenceCount: 150,
    confidence: 0.42,
    bandAdjustments: Array.from({ length: 10 }, (_, index) => index * 0.1),
    bassAdjustment: 0.4,
    trebleAdjustment: -0.2,
    surroundAdjustment: 0.03,
    reverbAdjustment: -0.01,
    stereoWidthAdjustment: 0.02,
    processingIntensityAdjustment: 0.06
  }
  value.populationTarget = proposal('population-base')
  value.populationTarget.gains = Array(10).fill(-1)
  value.personalizedTarget = proposal('personalized-base')
  value.personalizedTarget.gains = Array(10).fill(2.5)

  const vector = trainingVectors(value)
  assert.ok(vector)
  assert.equal(vector.learningConditioned, false)
  assert.equal(vector.x[featureNames.indexOf('learning.active')], 0)
  assert.equal(vector.x[featureNames.indexOf('learning.confidence')], 0)
  assert.equal(vector.x[featureNames.indexOf('tenBand.learning.bandAdjustments.9')], 0)
  assert.deepEqual(vector.y.slice(0, 10), Array(10).fill(-1))
  assert.equal(vector.deviceConditioned, false)
})

test('manual equalizer edits become a delta on the population target, not the heard curve', () => {
  const value = sample('manual-edit')
  value.feedback = 'manualEqualizer'
  value.populationTarget = proposal('population-base')
  value.populationTarget.gains = Array(10).fill(-1)
  value.target.gains = Array(10).fill(2)
  value.manualGainsDB = Array.from({ length: 10 }, (_, index) => (index === 0 ? 5 : 2))

  const vector = trainingVectors(value)
  assert.ok(vector)
  assert.equal(vector.manualCorrected, true)
  assert.equal(vector.sampleWeight, 1.35)
  assert.equal(vector.y[0], 2)
  assert.deepEqual(vector.y.slice(1, 10), Array(9).fill(-1))

  const withoutCurve = sample('manual-edit-no-curve')
  withoutCurve.feedback = 'manualEqualizer'
  const fallback = trainingVectors(withoutCurve)
  assert.equal(fallback.manualCorrected, false)
  assert.equal(fallback.sampleWeight, 0.45)
})

test('self-generated proposals are recognised and excluded from the dataset', () => {
  assert.equal(isSelfGeneratedProposal({
    provider: 'appleIntelligence',
    model: 'mono-resonance-s1-schema6-20260903075842-874351d7',
    skillCompliance: { executionMode: 'trainedCoreMLModel' }
  }), true)
  assert.equal(isSelfGeneratedProposal({
    provider: 'openAICompatible',
    model: 'gpt-5.6-sol',
    skillCompliance: { executionMode: 'appleIntelligenceLocalCompiler' }
  }), true)
  assert.equal(isSelfGeneratedProposal({
    provider: 'openAICompatible',
    model: 'gpt-5.6-sol',
    skillCompliance: { executionMode: 'requiredModelTool' }
  }), false)

  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-selfgen-'))
  try {
    const human = sample('human-1')
    const machine = sample('machine-1')
    machine.target.provider = 'appleIntelligence'
    machine.target.model = 'mono-resonance-s1-schema6-x'
    machine.target.skillCompliance.executionMode = 'trainedCoreMLModel'
    const legacyMachine = proposal('machine-legacy')
    legacyMachine.provider = 'appleIntelligence'
    legacyMachine.skillCompliance.executionMode = 'trainedCoreMLModel'
    const cloudDatabasePath = createCloudDatabase(directory, [{
      aiEqualizer: {
        cachedProposals: { [legacyMachine.id]: legacyMachine },
        savedProposals: {
          [human.songIdentifier]: [{ id: human.id, proposal: human.target }],
          [machine.songIdentifier]: [{ id: machine.id, proposal: machine.target }]
        },
        trainingSamples: { [human.id]: human, [machine.id]: machine }
      }
    }])
    const { stats, examples } = collectDataset(cloudDatabasePath, { includeVectors: true })
    assert.equal(stats.completeSamples, 1)
    assert.equal(stats.legacyPlans, 0)
    assert.equal(stats.selfGeneratedSamples, 1)
    assert.equal(stats.selfGeneratedPlans, 1)
    assert.equal(stats.completeAccounts, 1)
    assert.deepEqual(examples.map((item) => item.id), ['human-1'])
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('dataset scan includes legacy plans as target-prior training samples', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-dataset-'))
  try {
    const completeId = 'complete-1'
    const legacyId = 'legacy-1'
    const cloudDatabasePath = createCloudDatabase(directory, [{
      aiEqualizer: {
        cachedProposals: {},
        savedProposals: {
          song: [{ id: completeId, proposal: proposal(completeId) }, { id: legacyId, proposal: proposal(legacyId) }]
        },
        trainingSamples: { [completeId]: sample(completeId) }
      }
    }])
    const collected = collectDataset(cloudDatabasePath, { includeVectors: true })
    const result = collected.stats
    assert.deepEqual(
      {
        snapshots: result.snapshotCount,
        accounts: result.contributingAccounts,
        complete: result.completeSamples,
        trainable: result.trainableSamples,
        total: result.totalPlans,
        legacy: result.legacyPlans
      },
      { snapshots: 1, accounts: 1, complete: 1, trainable: 2, total: 2, legacy: 1 }
    )
    assert.deepEqual(collected.examples.map((item) => item.source).sort(), ['complete', 'legacy'])
    assert.equal(collected.examples.find((item) => item.source === 'legacy').x, null)
    assert.equal(result.styleConditionedSamples, 1)
    assert.equal(result.standardProfileSamples, 0)
    assert.equal(result.spatialProfileSamples, 2)
    assert.equal(collected.examples.find((item) => item.source === 'complete').styleConditioned, true)
    assert.equal(Object.prototype.hasOwnProperty.call(result, 'tokenIds'), false)
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('rejected complete samples are excluded instead of becoming legacy priors', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-rejected-'))
  try {
    const id = 'rejected-plan'
    const value = sample(id)
    value.feedback = 'regenerated'
    const cloudDatabasePath = createCloudDatabase(directory, [{
      aiEqualizer: {
        cachedProposals: {},
        savedProposals: { [value.songIdentifier]: [{ id, proposal: value.target }] },
        trainingSamples: { [id]: value }
      }
    }])
    const collected = collectDataset(cloudDatabasePath, { includeVectors: true })
    assert.equal(collected.stats.excludedOutcomeSamples, 1)
    assert.equal(collected.stats.completeSamples, 0)
    assert.equal(collected.stats.legacyPlans, 0)
    assert.equal(collected.stats.trainableSamples, 0)
    assert.deepEqual(collected.examples, [])
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('training service persists a completed residual model', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-service-'))
  try {
    const snapshots = Array.from({ length: 6 }, (_, index) => {
      const id = `sample-${index}`
      const mode = [2, 3, 5].includes(index) ? 'thirtyTwoBand' : 'tenBand'
      const value = sample(id, mode)
      value.target.tuningProfile = index % 2 === 0
        ? 'standard'
        : 'monoSpatialEnhancement'
      return {
        aiEqualizer: {
          cachedProposals: {},
          savedProposals: { song: [{ id, proposal: value.target }] },
          trainingSamples: { [id]: value }
        }
      }
    })
    const cloudDatabasePath = createCloudDatabase(directory, snapshots)
    const service = createAudioTuningTrainingService({
      directory: path.join(directory, 'training'),
      cloudDatabasePath,
      coreMLExporter: fakeCoreMLExporter,
      logger: { error() {} }
    })
    service.updateSettings({ epochs: 2, hiddenUnits: 4, minimumSamples: 4, targetMode: 'population' })
    service.startTraining('full-admin')
    let state = service.status()
    for (let attempt = 0; attempt < 200 && state.currentJob?.isActive; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.equal(state.currentJob.state, 'completed')
    assert.equal(state.currentJob.progress, 1)
    assert.ok(state.currentModel)
    assert.equal(state.currentModel.sampleCount, 6)
    assert.equal(state.currentModel.targetSchemaVersion, 4)
    assert.equal(state.currentModel.coreMLArtifact.byteCount, 512)
    assert.equal(state.currentModel.coreMLArtifact.format, 'coreml-neuralnetwork-v2')
    const model = service.modelArtifact(state.currentModel.id)
    assert.equal(model.artifact.architecture, MODEL_ARCHITECTURE)
    assert.equal(MODEL_FAMILY, 'Mono Resonance')
    assert.equal(MODEL_NAME, 'Mono Resonance S2')
    assert.equal(MODEL_VERSION_PREFIX, 'mono-resonance-s2-schema7')
    assert.equal(model.artifact.modelFamily, MODEL_FAMILY)
    assert.equal(model.artifact.modelName, MODEL_NAME)
    assert.equal(model.featureSchemaVersion, 7)
    assert.deepEqual(model.artifact.graphicEQModes, ['tenBand', 'thirtyTwoBand'])
    assert.equal(model.artifact.targetNames.length, 197)
    assert.match(model.version, /^mono-resonance-s2-schema7-/)
    assert.equal(
      (model.metrics.tenBandTrainingSamples || 0)
        + (model.metrics.tenBandValidationSamples || 0),
      3
    )
    assert.equal(
      (model.metrics.thirtyTwoBandTrainingSamples || 0)
        + (model.metrics.thirtyTwoBandValidationSamples || 0),
      3
    )
    assert.equal(model.metrics.styleConditionedTrainingSamples
      + model.metrics.styleConditionedValidationSamples, 6)
    assert.equal(model.metrics.standardProfileTrainingSamples
      + model.metrics.standardProfileValidationSamples, 3)
    assert.equal(model.metrics.spatialProfileTrainingSamples
      + model.metrics.spatialProfileValidationSamples, 3)
    assert.ok(model.artifact.outputHeadWeights.flat().some((value) => Math.abs(value) > 0.0001))
    assert.equal(model.artifact.outputWeights, undefined)
    assert.ok(model.metrics.initialTrainingLoss > model.metrics.trainingLoss)
    assert.ok(model.metrics.optimizationSteps > 0)

    const { DatabaseSync } = require('node:sqlite')
    const database = new DatabaseSync(service.databasePath)
    database.prepare(`UPDATE audio_training_model_artifacts
      SET format = 'coreml-neuralnetwork' WHERE model_id = ?`).run(state.currentModel.id)
    database.close()
    assert.equal(service.status().currentModel.coreMLArtifact, null)
    const regenerated = await service.ensureCoreMLArtifact(state.currentModel.id)
    assert.equal(regenerated.format, 'coreml-neuralnetwork-v2')
    service.close()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('training refuses a model missing a required 10-band profile branch', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-coverage-'))
  try {
    const snapshots = Array.from({ length: 4 }, (_, index) => {
      const id = `incomplete-${index}`
      const value = sample(id)
      return {
        aiEqualizer: {
          cachedProposals: {},
          savedProposals: { song: [{ id, proposal: value.target }] },
          trainingSamples: { [id]: value }
        }
      }
    })
    const cloudDatabasePath = createCloudDatabase(directory, snapshots)
    const service = createAudioTuningTrainingService({
      directory: path.join(directory, 'training'),
      cloudDatabasePath,
      coreMLExporter: fakeCoreMLExporter,
      logger: { error() {} }
    })
    service.updateSettings({ minimumSamples: 4 })
    assert.throws(
      () => service.startTraining('full-admin'),
      (error) => error?.code === 'INSUFFICIENT_BRANCH_COVERAGE'
    )
    service.close()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('song style inputs learn different tuning outputs', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-style-'))
  try {
    const snapshots = Array.from({ length: 24 }, (_, index) => {
      const id = `style-${index}`
      const value = sample(id)
      const rock = index % 2 === 0
      value.features.genreHints = [rock ? 'rock' : 'ballad']
      value.features.instrumentHints = [rock ? 'drums' : 'piano']
      value.features.genreScores = { [rock ? 'rock' : 'ballad']: 0.92 }
      value.features.instrumentScores = { [rock ? 'drums' : 'piano']: 0.88 }
      value.target.gains = Array(10).fill(rock ? 3 : -3)
      return {
        aiEqualizer: {
          cachedProposals: {},
          savedProposals: { song: [{ id, proposal: value.target }] },
          trainingSamples: { [id]: value }
        }
      }
    })
    const cloudDatabasePath = createCoveredCloudDatabase(directory, snapshots, 'style')
    const service = createAudioTuningTrainingService({
      directory: path.join(directory, 'training'),
      cloudDatabasePath,
      coreMLExporter: fakeCoreMLExporter,
      logger: { error() {} }
    })
    service.updateSettings({
      epochs: 60,
      hiddenUnits: 16,
      learningRate: 0.01,
      minimumSamples: 4,
      validationPercent: 20
    })
    service.startTraining('full-admin')
    let state = service.status()
    for (let attempt = 0; attempt < 400 && state.currentJob?.isActive; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.equal(state.currentJob.state, 'completed')
    const model = service.modelArtifact(state.currentModel.id)
    const rockSample = sample('prediction-rock')
    rockSample.features.genreHints = ['rock']
    rockSample.features.instrumentHints = ['drums']
    rockSample.features.genreScores = { rock: 0.92 }
    rockSample.features.instrumentScores = { drums: 0.88 }
    const balladSample = sample('prediction-ballad')
    balladSample.features.genreHints = ['ballad']
    balladSample.features.instrumentHints = ['piano']
    balladSample.features.genreScores = { ballad: 0.92 }
    balladSample.features.instrumentScores = { piano: 0.88 }
    const rockOutput = artifactPrediction(model.artifact, trainingVectors(rockSample).x)
    const balladOutput = artifactPrediction(model.artifact, trainingVectors(balladSample).x)
    const styleDelta = Math.max(...rockOutput.slice(0, 10).map(
      (value, index) => Math.abs(value - balladOutput[index])
    ))
    assert.ok(styleDelta > 1, `expected learned style response, received ${styleDelta}`)
    service.close()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('standard and spatial profiles learn different spatial outputs', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-profile-'))
  try {
    const snapshots = Array.from({ length: 24 }, (_, index) => {
      const id = `profile-${index}`
      const value = sample(id)
      const isSpatial = index % 2 === 0
      value.target.tuningProfile = isSpatial ? 'monoSpatialEnhancement' : 'standard'
      value.target.spatial = isSpatial
        ? { surroundLevel: 0.55, reverbLevel: 0.32, stereoWidth: 1.42 }
        : { surroundLevel: 0.02, reverbLevel: 0.01, stereoWidth: 1.02 }
      value.target.enhance.stageWidth = isSpatial ? 0.68 : 0.06
      return {
        aiEqualizer: {
          cachedProposals: {},
          savedProposals: { [value.songIdentifier]: [{ id, proposal: value.target }] },
          trainingSamples: { [id]: value }
        }
      }
    })
    const cloudDatabasePath = createCoveredCloudDatabase(directory, snapshots, 'profile')
    const service = createAudioTuningTrainingService({
      directory: path.join(directory, 'training'),
      cloudDatabasePath,
      coreMLExporter: fakeCoreMLExporter,
      logger: { error() {} }
    })
    service.updateSettings({
      epochs: 60,
      hiddenUnits: 16,
      learningRate: 0.01,
      minimumSamples: 4,
      validationPercent: 20
    })
    service.startTraining('full-admin')
    let state = service.status()
    for (let attempt = 0; attempt < 400 && state.currentJob?.isActive; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.equal(state.currentJob.state, 'completed')
    const model = service.modelArtifact(state.currentModel.id)
    assert.equal(model.metrics.standardProfileTrainingSamples
      + model.metrics.standardProfileValidationSamples + model.metrics.standardProfileCalibrationSamples, 14)
    assert.equal(model.metrics.spatialProfileTrainingSamples
      + model.metrics.spatialProfileValidationSamples + model.metrics.spatialProfileCalibrationSamples, 14)

    for (const mode of ['tenBand', 'thirtyTwoBand']) {
      const standard = sample(`prediction-profile-standard-${mode}`, mode)
      standard.target.tuningProfile = 'standard'
      const spatial = sample(`prediction-profile-spatial-${mode}`, mode)
      spatial.target.tuningProfile = 'monoSpatialEnhancement'
      const standardOutput = artifactPrediction(model.artifact, trainingVectors(standard).x)
      const spatialOutput = artifactPrediction(model.artifact, trainingVectors(spatial).x)
      const difference = (name) => {
        const index = targetNames.indexOf(name)
        return spatialOutput[index] - standardOutput[index]
      }
      assert.ok(difference('spatial.surroundLevel') >= 0.02, `${mode} surround direction`)
      assert.ok(difference('spatial.stereoWidth') >= 0.03, `${mode} stereo-width direction`)
      assert.ok(difference('enhance.stageWidth') >= 0.02, `${mode} stage-width direction`)
    }
    service.close()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('legacy plans retain profile-conditioned spatial priors', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-legacy-profile-'))
  try {
    const snapshots = Array.from({ length: 24 }, (_, index) => {
      const id = `legacy-profile-${index}`
      const target = proposal(id)
      const isSpatial = index % 2 === 0
      target.tuningProfile = isSpatial ? 'monoSpatialEnhancement' : 'standard'
      target.spatial = isSpatial
        ? { surroundLevel: 0.6, reverbLevel: 0.34, stereoWidth: 1.48 }
        : { surroundLevel: 0.01, reverbLevel: 0.01, stereoWidth: 1.01 }
      target.enhance.stageWidth = isSpatial ? 0.72 : 0.04
      return {
        aiEqualizer: {
          cachedProposals: {},
          savedProposals: { song: [{ id, proposal: target }] }
        }
      }
    })
    const cloudDatabasePath = createCoveredCloudDatabase(directory, snapshots, 'legacy-profile')
    const service = createAudioTuningTrainingService({
      directory: path.join(directory, 'training'),
      cloudDatabasePath,
      coreMLExporter: fakeCoreMLExporter,
      logger: { error() {} }
    })
    service.updateSettings({
      epochs: 80,
      hiddenUnits: 16,
      learningRate: 0.01,
      minimumSamples: 4,
      validationPercent: 20
    })
    service.startTraining('full-admin')
    let state = service.status()
    for (let attempt = 0; attempt < 500 && state.currentJob?.isActive; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.equal(state.currentJob.state, 'completed')
    const model = service.modelArtifact(state.currentModel.id)
    assert.equal(model.metrics.legacyPriorBranches, 4)

    const standardInput = Array(featureNames.length).fill(0)
    const spatialInput = Array(featureNames.length).fill(0)
    standardInput[featureNames.indexOf('tuningProfile.standard')] = 1
    spatialInput[featureNames.indexOf('tuningProfile.monoSpatialEnhancement')] = 1
    const standardOutput = artifactPrediction(model.artifact, standardInput)
    const spatialOutput = artifactPrediction(model.artifact, spatialInput)
    const profileDifferences = Object.fromEntries([
      'spatial.surroundLevel',
      'spatial.reverbLevel',
      'spatial.stereoWidth',
      'enhance.stageWidth'
    ].map((name) => {
      const index = targetNames.indexOf(name)
      return [name, spatialOutput[index] - standardOutput[index]]
    }))
    assert.ok(profileDifferences['spatial.surroundLevel'] >= 0.02)
    assert.ok(profileDifferences['spatial.stereoWidth'] >= 0.03)
    assert.ok(profileDifferences['enhance.stageWidth'] >= 0.02)
    service.close()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('same-style tracks learn different tuning from temporal fingerprints', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-track-'))
  try {
    const snapshots = Array.from({ length: 24 }, (_, index) => {
      const id = `track-${index}`
      const value = sample(id)
      const brightChorus = index % 2 === 0
      value.features.genreHints = ['rock']
      value.features.instrumentHints = ['drums', 'guitar']
      value.features.genreScores = { rock: 0.86 }
      value.features.instrumentScores = { drums: 0.78, guitar: 0.74 }
      value.features.bandEnergySpreadDB = Array(10).fill(brightChorus ? 2 : 11)
      value.features.sectionBandEnergyDB = Array.from({ length: 3 }, (_, section) =>
        Array(10).fill(brightChorus ? -5 - section : -24 + section))
      value.features.spectralCentroidP90Hz = brightChorus ? 6800 : 2100
      value.features.spectralFluxP90 = brightChorus ? 0.8 : 0.12
      value.target.gains = Array(10).fill(brightChorus ? -2.5 : 2.5)
      return {
        aiEqualizer: {
          cachedProposals: {},
          savedProposals: { [value.songIdentifier]: [{ id, proposal: value.target }] },
          trainingSamples: { [id]: value }
        }
      }
    })
    const cloudDatabasePath = createCoveredCloudDatabase(directory, snapshots, 'track')
    const service = createAudioTuningTrainingService({
      directory: path.join(directory, 'training'),
      cloudDatabasePath,
      coreMLExporter: fakeCoreMLExporter,
      logger: { error() {} }
    })
    service.updateSettings({
      epochs: 60,
      hiddenUnits: 16,
      learningRate: 0.01,
      minimumSamples: 4,
      validationPercent: 20
    })
    service.startTraining('full-admin')
    let state = service.status()
    for (let attempt = 0; attempt < 400 && state.currentJob?.isActive; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.equal(state.currentJob.state, 'completed')
    const model = service.modelArtifact(state.currentModel.id)
    const first = sample('prediction-rock-a')
    const second = sample('prediction-rock-b')
    for (const value of [first, second]) {
      value.features.genreHints = ['rock']
      value.features.instrumentHints = ['drums', 'guitar']
      value.features.genreScores = { rock: 0.86 }
      value.features.instrumentScores = { drums: 0.78, guitar: 0.74 }
    }
    first.features.bandEnergySpreadDB = Array(10).fill(2)
    first.features.sectionBandEnergyDB = Array.from({ length: 3 }, (_, section) =>
      Array(10).fill(-5 - section))
    first.features.spectralCentroidP90Hz = 6800
    first.features.spectralFluxP90 = 0.8
    second.features.bandEnergySpreadDB = Array(10).fill(11)
    second.features.sectionBandEnergyDB = Array.from({ length: 3 }, (_, section) =>
      Array(10).fill(-24 + section))
    second.features.spectralCentroidP90Hz = 2100
    second.features.spectralFluxP90 = 0.12
    const firstOutput = artifactPrediction(model.artifact, trainingVectors(first).x)
    const secondOutput = artifactPrediction(model.artifact, trainingVectors(second).x)
    const trackDelta = Math.max(...firstOutput.slice(0, 10).map(
      (value, index) => Math.abs(value - secondOutput[index])
    ))
    assert.ok(trackDelta > 1, `expected learned per-track response, received ${trackDelta}`)
    service.close()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('agent learning context changes the learned tuning for otherwise matching inputs', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-learning-'))
  try {
    const snapshots = Array.from({ length: 24 }, (_, index) => {
      const id = `learning-${index}`
      const value = sample(id)
      const warmer = index % 2 === 0
      value.features.genreHints = ['pop']
      value.features.instrumentHints = ['vocals']
      value.features.genreScores = { pop: 0.9 }
      value.features.instrumentScores = { vocals: 0.85 }
      value.learningContext = {
        revision: index + 1,
        evidenceCount: 12,
        confidence: 0.36,
        bandAdjustments: Array(10).fill(warmer ? 1 : -1),
        bassAdjustment: warmer ? 0.8 : -0.8,
        trebleAdjustment: warmer ? -0.3 : 0.3,
        surroundAdjustment: 0,
        reverbAdjustment: 0,
        stereoWidthAdjustment: 0,
        processingIntensityAdjustment: 0
      }
      value.populationTarget = proposal(`population-${index}`)
      value.populationTarget.gains = Array(10).fill(0)
      value.personalizedTarget = proposal(`personalized-${index}`)
      value.personalizedTarget.gains = Array(10).fill(warmer ? 3 : -3)
      return {
        aiEqualizer: {
          cachedProposals: {},
          savedProposals: { [value.songIdentifier]: [{ id, proposal: value.target }] },
          trainingSamples: { [id]: value }
        }
      }
    })
    const cloudDatabasePath = createCoveredCloudDatabase(directory, snapshots, 'learning')
    const service = createAudioTuningTrainingService({
      directory: path.join(directory, 'training'),
      cloudDatabasePath,
      coreMLExporter: fakeCoreMLExporter,
      logger: { error() {} }
    })
    service.updateSettings({
      epochs: 80,
      hiddenUnits: 16,
      learningRate: 0.01,
      minimumSamples: 4,
      validationPercent: 20,
      targetMode: 'personalized'
    })
    service.startTraining('full-admin')
    let state = service.status()
    for (let attempt = 0; attempt < 500 && state.currentJob?.isActive; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.equal(state.currentJob.state, 'completed')
    const model = service.modelArtifact(state.currentModel.id)
    assert.equal(model.metrics.targetMode, 'personalized')
    assert.equal(
      (model.metrics.learningConditionedTrainingSamples ?? 0)
        + (model.metrics.learningConditionedValidationSamples ?? 0)
        + (model.metrics.learningConditionedCalibrationSamples ?? 0),
      24
    )

    const warm = sample('prediction-learning-warm')
    const cool = sample('prediction-learning-cool')
    for (const [value, adjustment] of [[warm, 1], [cool, -1]]) {
      value.features.genreHints = ['pop']
      value.features.instrumentHints = ['vocals']
      value.features.genreScores = { pop: 0.9 }
      value.features.instrumentScores = { vocals: 0.85 }
      value.learningContext = {
        evidenceCount: 12,
        confidence: 0.36,
        bandAdjustments: Array(10).fill(adjustment),
        bassAdjustment: adjustment * 0.8,
        trebleAdjustment: adjustment * -0.3,
        surroundAdjustment: 0,
        reverbAdjustment: 0,
        stereoWidthAdjustment: 0,
        processingIntensityAdjustment: 0
      }
      value.personalizedTarget = proposal(`prediction-${adjustment}`)
    }
    const warmOutput = artifactPrediction(
      model.artifact,
      trainingVectors(warm, { targetMode: 'personalized' }).x
    )
    const coolOutput = artifactPrediction(
      model.artifact,
      trainingVectors(cool, { targetMode: 'personalized' }).x
    )
    const learningDelta = Math.max(...warmOutput.slice(0, 10).map(
      (value, index) => Math.abs(value - coolOutput[index])
    ))
    assert.ok(learningDelta > 1, `expected learned preference response, received ${learningDelta}`)
    service.close()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('detailed device parameters change learned tuning for otherwise matching tracks', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-device-'))
  try {
    const snapshots = Array.from({ length: 24 }, (_, index) => {
      const id = `device-${index}`
      const value = sample(id)
      const opra = index % 2 === 0
      value.features.genreHints = ['pop']
      value.features.instrumentHints = ['vocals']
      value.features.genreScores = { pop: 0.9 }
      value.features.instrumentScores = { vocals: 0.85 }
      value.deviceContext = detailedDeviceContext({
        source: opra ? 'opra' : 'custom',
        gain: opra ? 1.5 : -1.5
      })
      value.populationTarget = proposal(`device-target-${index}`)
      value.populationTarget.gains = Array(10).fill(opra ? 2.5 : -2.5)
      return {
        aiEqualizer: {
          cachedProposals: {},
          savedProposals: { [value.songIdentifier]: [{ id, proposal: value.target }] },
          trainingSamples: { [id]: value }
        }
      }
    })
    const cloudDatabasePath = createCoveredCloudDatabase(directory, snapshots, 'device')
    const service = createAudioTuningTrainingService({
      directory: path.join(directory, 'training'),
      cloudDatabasePath,
      coreMLExporter: fakeCoreMLExporter,
      logger: { error() {} }
    })
    service.updateSettings({
      epochs: 80,
      hiddenUnits: 16,
      learningRate: 0.01,
      minimumSamples: 4,
      validationPercent: 20
    })
    service.startTraining('full-admin')
    let state = service.status()
    for (let attempt = 0; attempt < 500 && state.currentJob?.isActive; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.equal(state.currentJob.state, 'completed')
    const model = service.modelArtifact(state.currentModel.id)
    assert.equal(
      (model.metrics.deviceConditionedTrainingSamples ?? 0)
        + (model.metrics.deviceConditionedValidationSamples ?? 0)
        + (model.metrics.deviceConditionedCalibrationSamples ?? 0),
      24
    )

    const opra = sample('prediction-device-opra')
    const custom = sample('prediction-device-custom')
    for (const [value, source, gain] of [
      [opra, 'opra', 1.5],
      [custom, 'custom', -1.5]
    ]) {
      value.features.genreHints = ['pop']
      value.features.instrumentHints = ['vocals']
      value.features.genreScores = { pop: 0.9 }
      value.features.instrumentScores = { vocals: 0.85 }
      value.deviceContext = detailedDeviceContext({ source, gain })
      value.populationTarget = proposal(`prediction-${source}`)
    }
    const opraOutput = artifactPrediction(model.artifact, trainingVectors(opra).x)
    const customOutput = artifactPrediction(model.artifact, trainingVectors(custom).x)
    const deviceDelta = Math.max(...opraOutput.slice(0, 10).map(
      (value, index) => Math.abs(value - customOutput[index])
    ))
    assert.ok(deviceDelta > 1, `expected learned device response, received ${deviceDelta}`)
    service.close()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('validation split keeps every sample for one track on the same side', () => {
  const examples = [
    { id: 'a1', trackGroup: 'track:a', accountBucket: 1, x: [1], y: [1] },
    { id: 'a2', trackGroup: 'track:a', accountBucket: 200, x: [2], y: [2] },
    { id: 'b1', trackGroup: 'track:b', accountBucket: 1, x: [3], y: [3] },
    { id: 'c1', trackGroup: 'track:c', accountBucket: 200, x: [4], y: [4] }
  ]
  const split = splitExamples(examples, 34)
  const trainingGroups = new Set(split.training.map((item) => item.trackGroup))
  const validationGroups = new Set(split.validation.map((item) => item.trackGroup))
  assert.equal([...trainingGroups].some((value) => validationGroups.has(value)), false)
  assert.equal(split.training.length + split.validation.length, examples.length)
})

test('validation split keeps every observed band and profile branch in training', () => {
  const examples = [
    { id: 'common-a', trackGroup: 'track:a', x: [1], y: [1], graphicEQMode: 'tenBand', tuningProfile: 'standard' },
    { id: 'common-b', trackGroup: 'track:b', x: [2], y: [2], graphicEQMode: 'tenBand', tuningProfile: 'standard' },
    { id: 'common-c', trackGroup: 'track:c', x: [3], y: [3], graphicEQMode: 'tenBand', tuningProfile: 'standard' },
    { id: 'ten-spatial', trackGroup: 'track:d', x: [4], y: [4], graphicEQMode: 'tenBand', tuningProfile: 'monoSpatialEnhancement' },
    { id: 'thirty-two-standard', trackGroup: 'track:e', x: [5], y: [5], graphicEQMode: 'thirtyTwoBand', tuningProfile: 'standard' },
    { id: 'thirty-two-spatial', trackGroup: 'track:f', x: [6], y: [6], graphicEQMode: 'thirtyTwoBand', tuningProfile: 'monoSpatialEnhancement' }
  ]
  const split = splitExamples(examples, 50)
  const trainingBranches = new Set(split.training.map(
    (item) => `${item.graphicEQMode}:${item.tuningProfile}`
  ))
  assert.deepEqual(trainingBranches, new Set([
    'tenBand:standard',
    'tenBand:monoSpatialEnhancement',
    'thirtyTwoBand:standard',
    'thirtyTwoBand:monoSpatialEnhancement'
  ]))
  assert.ok(split.validation.length > 0)
})

test('legacy prior weight is normalized as one dataset when complete inputs exist', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-mixed-'))
  try {
    function mixedSnapshot(prefix) {
      const entries = []
      const trainingSamples = {}
      for (let index = 0; index < 6; index += 1) {
        const id = `${prefix}-${index}`
        const [mode, profile] = [
          ['tenBand', 'standard'],
          ['tenBand', 'monoSpatialEnhancement'],
          ['thirtyTwoBand', 'standard'],
          ['thirtyTwoBand', 'monoSpatialEnhancement']
        ][index % 4]
        const target = proposal(id, mode)
        target.tuningProfile = profile
        entries.push({ id, proposal: target })
        if (index % 2 === 0) {
          const value = sample(id, mode)
          value.target = target
          trainingSamples[id] = value
        }
      }
      return {
        aiEqualizer: {
          cachedProposals: {},
          savedProposals: { song: entries },
          trainingSamples
        }
      }
    }
    const cloudDatabasePath = createCloudDatabase(directory, [
      mixedSnapshot('training'),
      mixedSnapshot('validation')
    ])
    const service = createAudioTuningTrainingService({
      directory: path.join(directory, 'training'),
      cloudDatabasePath,
      coreMLExporter: fakeCoreMLExporter,
      logger: { error() {} }
    })
    service.updateSettings({ epochs: 2, hiddenUnits: 4, minimumSamples: 4, priorWeight: 0.5 })
    service.startTraining('full-admin')
    let state = service.status()
    for (let attempt = 0; attempt < 200 && state.currentJob?.isActive; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.equal(state.currentJob.state, 'completed')
    const metrics = service.modelArtifact(state.currentModel.id).metrics
    assert.ok(metrics.completeTrainingSamples > 0)
    assert.ok(metrics.legacyTrainingSamples > 0)
    // Supervised examples average to weight 1; the whole legacy prior carries
    // priorWeight times that mass regardless of how many plans exist.
    assert.equal(metrics.supervisedTotalWeight, metrics.completeTrainingSamples)
    assert.ok(Math.abs(metrics.legacyTotalWeight - 0.5 * metrics.completeTrainingSamples) < 1e-9)
    assert.ok(Math.abs(
      metrics.legacyPerSampleWeight - metrics.legacyTotalWeight / metrics.legacyTrainingSamples
    ) < 1e-9)
    assert.equal(metrics.legacyPriorWeight, 0.5)
    service.close()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('training service can train a population prior from legacy-only plans', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-legacy-'))
  try {
    const snapshots = Array.from({ length: 6 }, (_, index) => {
      const id = `legacy-${index}`
      const [mode, profile] = [
        ['tenBand', 'standard'],
        ['tenBand', 'monoSpatialEnhancement'],
        ['thirtyTwoBand', 'standard'],
        ['thirtyTwoBand', 'monoSpatialEnhancement']
      ][index % 4]
      const target = proposal(id, mode)
      target.tuningProfile = profile
      return {
        aiEqualizer: {
          cachedProposals: {},
          savedProposals: { song: [{ id, proposal: target }] }
        }
      }
    })
    const cloudDatabasePath = createCloudDatabase(directory, snapshots)
    const service = createAudioTuningTrainingService({
      directory: path.join(directory, 'training'),
      cloudDatabasePath,
      coreMLExporter: fakeCoreMLExporter,
      logger: { error() {} }
    })
    service.updateSettings({ epochs: 2, hiddenUnits: 4, minimumSamples: 4, targetMode: 'population' })
    service.startTraining('full-admin')
    let state = service.status()
    for (let attempt = 0; attempt < 200 && state.currentJob?.isActive; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.equal(state.currentJob.state, 'completed')
    assert.equal(state.currentJob.sampleCount, 6)
    assert.equal(state.currentModel.sampleCount, 6)
    const model = service.modelArtifact(state.currentModel.id)
    assert.match(model.artifact.trainingStrategy, /population-target-account-damped-legacy-prior/)
    assert.equal(model.artifact.targetMode, 'population')
    assert.equal(model.artifact.inputNormalization.mean.length, featureNames.length)
    assert.ok(model.artifact.hiddenWeights.flat().some((value) => Math.abs(value) > 0.0001))
    assert.ok(model.artifact.outputHeadWeights.flat().some((value) => Math.abs(value) > 0.0001))
    assert.ok(model.artifact.outputHeadBias.some((value) => Math.abs(value) > 0.0001))
    assert.ok(model.metrics.initialTrainingLoss > model.metrics.trainingLoss)
    assert.equal(model.metrics.validationSamples, 0)
    assert.equal(model.metrics.initialValidationLoss, null)
    assert.equal(model.metrics.validationLoss, null)
    assert.ok(model.metrics.trainingLossImprovement > 0)
    assert.equal(model.metrics.validationLossImprovement, null)
    // Tiny datasets fall back to single-example batches, so every plan is one step.
    assert.equal(
      model.metrics.optimizationSteps,
      model.metrics.legacyTrainingSamples * 2
    )
    assert.ok(model.metrics.qualityWarnings.includes('NO_COMPLETE_SAMPLES'))
    assert.equal(
      model.metrics.legacyTrainingSamples + model.metrics.legacyValidationSamples,
      6
    )
    service.close()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('local-model human corrections supervise only native EQ and retain the rejected curve', () => {
  for (const mode of ['tenBand', 'thirtyTwoBand']) {
    const value = sample(`manual-local-${mode}`, mode)
    const bands = mode === 'tenBand' ? 10 : 32
    const offset = mode === 'tenBand' ? 0 : 10
    value.target.model = 'mono-resonance-s1-test'
    value.target.skillCompliance.executionMode = 'trainedCoreMLModel'
    value.feedback = 'manualEqualizer'
    value.manualGainsDB = value.target.gains.map((gain) => gain + 1)
    const vector = trainingVectors(value)
    assert.ok(vector)
    assert.equal(vector.targetMask.reduce((a, b) => a + b, 0), bands)
    assert.equal(vector.preferenceMask.reduce((a, b) => a + b, 0), bands)
    assert.equal(vector.y[offset], vector.rejectedY[offset] + 1)
    assert.ok(vector.targetMask.slice(42).every((mask) => mask === 0))
    value.feedback = 'retained'
    assert.equal(trainingVectors(value), null)
  }
})

test('professional targets preserve detailed parameters with missing and inactive slots masked', () => {
  for (const mode of ['tenBand', 'thirtyTwoBand']) {
    const value = sample(`professional-${mode}`, mode)
    value.target.professional.dynamicEQ = { enabled: true, bands: [
      { frequency: 6200, q: 1.8, thresholdDB: -21, ratio: 2.4, maxReductionDB: 3.2, attackMS: 7, releaseMS: 140 },
      { frequency: 180, q: 0.8, thresholdDB: -25, ratio: 1.8, maxReductionDB: 2.1, attackMS: 26, releaseMS: 210 }
    ] }
    value.target.professional.parametricEQ = { enabled: true, bands: [
      { type: 'highShelf', frequency: 7300, gainDB: -2.5, q: 0.7 }
    ] }
    value.target.professional.multiband = {
      enabled: false, lowCrossoverHz: 230, highCrossoverHz: 4200,
      thresholdsDB: [-20, -18, -21], ratios: [2.3, 1.7, 2.1], maxReductionDB: [3, 2, 4],
      attackMS: 17, releaseMS: 230
    }
    const vector = trainingVectors(value)
    const at = (name) => vector.y[targetNames.indexOf(`professional.${name}`)]
    const mask = (name) => vector.targetMask[targetNames.indexOf(`professional.${name}`)]
    assert.equal(at('dynamicEQ.bands.0.frequency'), 180)
    assert.equal(at('dynamicEQ.bands.1.thresholdDB'), -21)
    assert.equal(at('parametricEQ.bands.0.type.highShelf'), 1)
    assert.equal(at('parametricEQ.bands.0.gainDB'), -2.5)
    assert.equal(at('multiband.ratios.0'), 2.3)
    assert.equal(at('multiband.highCrossoverHz'), 4200)
    assert.equal(mask('dynamicEQ.bands.2.frequency'), 0)
    assert.equal(mask('parametricEQ.bands.3.active'), mode === 'tenBand' ? 1 : 0)
    assert.equal(vector.y.length, 197)
  }
  const missing = trainingVectors(sample('missing-professional'))
  assert.ok(missing.targetMask.slice(92).every((value) => value === 0))
})

test('joint collection pairs population and personal context without duplicating recordings or self-labels', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-joint-training-'))
  try {
    const value = sample('joint-recording')
    value.learningContext = { confidence: 0.8, evidenceCount: 12, bandAdjustments: Array(10).fill(1) }
    value.populationTarget = proposal('joint-population')
    value.populationTarget.gains = Array(10).fill(0)
    value.personalizedTarget = proposal('joint-personal')
    value.personalizedTarget.gains = Array(10).fill(2)
    value.feedback = 'manualEqualizer'
    value.manualGainsDB = value.target.gains.map((gain) => gain + 1)
    const local = structuredClone(value)
    local.id = local.target.id = 'joint-local'
    local.target.model = 'mono-resonance-s1-test'
    const cloudDatabasePath = createCloudDatabase(directory, [{ aiEqualizer: {
      cachedProposals: { remote: value.target, local: local.target },
      trainingSamples: { remote: value, local }
    } }])
    const collected = collectDataset(cloudDatabasePath, { includeVectors: true, targetMode: 'joint' })
    assert.equal(collected.stats.completeSamples, 2)
    assert.equal(collected.stats.learningConditionedSamples, 2)
    const pair = collected.examples.find((item) => item.id === value.id)
    assert.equal(pair.x[featureNames.indexOf('learning.active')], 1)
    assert.equal(pair.y[0], 3)
    assert.equal(pair.populationPair.y[0], 0)
    assert.equal(pair.populationPair.x[featureNames.indexOf('learning.active')], 0)
    assert.equal(collected.examples.find((item) => item.id === local.id).populationPair, null)
    assert.equal(normalizeSettings({}).targetMode, 'joint')
    assert.equal(normalizeSettings({ targetMode: 'population' }).targetMode, 'population')
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('training learns manual preference pairs and reports unknown validation branches honestly', () => {
  const examples = Array.from({ length: 24 }, (_, index) => {
    const value = sample(`preference-${index}`)
    value.target.model = 'mono-resonance-s1-test'
    value.target.gains = Array(10).fill(-2)
    value.feedback = 'manualEqualizer'
    value.manualGainsDB = Array(10).fill(2)
    return { ...trainingVectors(value), id: value.id, accountId: `account-${index % 4}`,
      trackGroup: value.songIdentifier, source: 'complete' }
  })
  const settings = normalizeSettings({ epochs: 35, hiddenUnits: 8, intentUnits: 4, earlyStoppingPatience: 0 })
  const trained = trainTinyModelSync({ training: examples.slice(0, 20), validation: examples.slice(20), settings })
  assert.equal(trained.preferenceTraining.count, 20)
  assert.equal(trained.preferenceValidation.count, 4)
  assert.equal(trained.preferenceValidation.accuracy, 1)
  assert.ok(artifactPrediction(trained, examples[0].x)[0] > 1)
  assert.equal(trained.branchValidation['thirtyTwoBand:standard'].eqMAEDB, null)
  assert.equal(trained.branchValidation['thirtyTwoBand:standard'].improvesPrior, null)
  assert.ok(Number.isFinite(trained.branchValidation['tenBand:monoSpatialEnhancement'].eqMAEDB))
  const unknown = targetNames.indexOf('professional.parametricEQ.bands.0.frequency')
  assert.equal(artifactPrediction(trained, examples[0].x)[unknown], 0)
})

test('one joint model learns a population baseline and opposite personal preferences for the same song features', () => {
  const examples = Array.from({ length: 40 }, (_, index) => {
    const value = sample(`joint-learn-${index}`)
    const adjustment = index % 2 ? 2 : -2
    value.learningContext = { confidence: 0.8, evidenceCount: 12, bandAdjustments: Array(10).fill(adjustment) }
    value.populationTarget = proposal('base')
    value.populationTarget.gains = Array(10).fill(0)
    value.personalizedTarget = proposal('personal')
    value.personalizedTarget.gains = Array(10).fill(adjustment)
    return { ...trainingVectors(value, { targetMode: 'joint' }),
      id: value.id, trackGroup: value.songIdentifier, accountId: `account-${index % 4}`, source: 'complete',
      populationPair: trainingVectors(value, { targetMode: 'population' }) }
  })
  const trained = trainTinyModelSync({
    training: examples.slice(0, 32), validation: examples.slice(32),
    settings: normalizeSettings({ epochs: 70, hiddenUnits: 12, intentUnits: 8, earlyStoppingPatience: 0 })
  })
  const cool = artifactPrediction(trained, examples[0].x)[0]
  const warm = artifactPrediction(trained, examples[1].x)[0]
  const baseline = artifactPrediction(trained, examples[0].populationPair.x)[0]
  assert.ok(cool < -1, `cool=${cool}`)
  assert.ok(warm > 1, `warm=${warm}`)
  assert.ok(Math.abs(baseline) < 0.6, `baseline=${baseline}`)
  assert.equal(trained.selectionValidationTracks, 8)
  assert.equal(trained.selectionSource, 'trainingLoss')
  assert.equal(trained.branchValidation['tenBand:monoSpatialEnhancement'].trackEQMAEP90DB, null)
})

test('residual model learns interacting style and device conditions, not only additive offsets', () => {
  const examples = Array.from({ length: 48 }, (_, index) => {
    const a = index % 2
    const b = Math.floor(index / 2) % 2
    const x = Array(featureNames.length).fill(0)
    x[featureNames.indexOf('genreScore.rock')] = a
    x[featureNames.indexOf('genreScore.acoustic')] = 1 - a
    x[featureNames.indexOf('outputKind.wired')] = b
    x[featureNames.indexOf('outputKind.bluetooth')] = 1 - b
    return { id: String(index), trackGroup: String(index), accountId: String(index % 3),
      graphicEQMode: 'tenBand', tuningProfile: 'standard', sampleWeight: 1,
      x, y: targetNames.map((_, slot) => slot < 10 ? (a === b ? 2 : -2) : 0),
      targetMask: targetNames.map((_, slot) => slot < 10 ? 1 : 0) }
  })
  const trained = trainTinyModelSync({ training: examples.slice(0, 32), validation: examples.slice(32),
    settings: normalizeSettings({ epochs: 60, hiddenUnits: 12, intentUnits: 4, earlyStoppingPatience: 0 }) })
  for (const example of examples.slice(32, 36)) {
    const predicted = artifactPrediction(trained, example.x)[0]
    assert.ok(Math.abs(predicted - example.y[0]) < 0.5, `${predicted} vs ${example.y[0]}`)
  }
  const branch = trained.branchValidation['tenBand:standard']
  assert.equal(branch.tracks, 16)
  assert.ok(branch.trackEQMAEP90DB < 0.5)
  assert.ok(branch.targetFamilyMSE.graphicEQ < 0.1)
  assert.equal(trained.conditionValidation['genreScore.rock'].samples, 8)
  assert.equal(trained.conditionValidation['genreScore.pop'].eqMAEDB, null)
  assert.equal(trained.selectionSource, 'heldOutTracks')
})

function productionShapedExamples({ completeCount, legacyPerBranch, completeAccount = 'dev' }) {
  const branches = [
    ['tenBand', 'standard'],
    ['tenBand', 'monoSpatialEnhancement'],
    ['thirtyTwoBand', 'standard'],
    ['thirtyTwoBand', 'monoSpatialEnhancement']
  ]
  const examples = []
  let counter = 0
  for (const [index, [mode, profile]] of branches.entries()) {
    const bandCount = mode === 'thirtyTwoBand' ? 32 : 10
    for (let item = 0; item < legacyPerBranch[index]; item += 1) {
      const id = `legacy-${counter++}`
      const target = proposal(id, mode)
      target.tuningProfile = profile
      target.tuningIntensity = 'smart'
      // Population prior: a clear tilt, 32-band deliberately larger so a flat
      // output is unambiguous.
      target.gains = Array.from({ length: bandCount }, (_, band) =>
        (band / (bandCount - 1)) * 6 - 3)
      target.preampDB = -5.5
      const vector = trainingVectors({
        schemaVersion: 4,
        id,
        songIdentifier: `netease:${id}`,
        features: { graphicEQMode: mode, bandEnergyDB: Array(bandCount).fill(-20) },
        deviceContext: { referenceGainsDB: Array(bandCount).fill(0) },
        target
      })
      examples.push({
        accountId: `legacy-account-${item % 7}`,
        trackGroup: `track:${id}`,
        id,
        graphicEQMode: mode,
        tuningProfile: profile,
        tuningIntensity: 'smart',
        source: 'legacy',
        x: null,
        y: vector.y,
        targetMask: vector.targetMask
      })
    }
  }
  for (let item = 0; item < completeCount; item += 1) {
    const id = `complete-${item}`
    const value = sample(id)
    value.feedback = 'retained'
    value.target.tuningProfile = 'standard'
    value.target.tuningIntensity = 'strong'
    value.features.bandEnergyDB = Array.from({ length: 10 }, (_, band) => -18 - band + (item % 3))
    value.populationTarget = proposal(`population-${id}`)
    value.populationTarget.tuningProfile = 'standard'
    // One account's private taste: bright and heavily attenuated.
    value.populationTarget.gains = Array.from({ length: 10 }, (_, band) => band * 0.6 - 2)
    value.populationTarget.preampDB = -9.5
    const vector = trainingVectors(value)
    examples.push({
      accountId: completeAccount,
      trackGroup: `track:${id}`,
      id,
      graphicEQMode: 'tenBand',
      tuningProfile: 'standard',
      tuningIntensity: 'strong',
      source: 'complete',
      sampleWeight: vector.sampleWeight,
      x: vector.x,
      y: vector.y,
      targetMask: vector.targetMask
    })
  }
  return examples
}

function legacyPrediction(result, mode, profile, intensity = 'smart') {
  const raw = [...result.inputNormalization.mean]
  const set = (name, value) => { raw[featureNames.indexOf(name)] = value }
  for (const [index, name] of featureNames.entries()) {
    if (name.startsWith(mode === 'thirtyTwoBand' ? 'tenBand.' : 'thirtyTwoBand.')) raw[index] = 0
    if (name.startsWith('learning.')) raw[index] = 0
  }
  set('graphicEQMode.thirtyTwoBand', mode === 'thirtyTwoBand' ? 1 : 0)
  set('tuningProfile.standard', profile === 'standard' ? 1 : 0)
  set('tuningProfile.monoSpatialEnhancement', profile === 'standard' ? 0 : 1)
  for (const value of ['smart', 'gentle', 'standard', 'strong']) {
    set(`tuningIntensity.${value}`, value === intensity ? 1 : 0)
  }
  return artifactPrediction(result, raw)
}

test('a single prolific account cannot overwrite the population prior for its branch', () => {
  const training = productionShapedExamples({
    completeCount: 48,
    legacyPerBranch: [400, 60, 40, 20]
  })
  const settings = require('./audio-tuning-training').normalizeSettings({
    epochs: 30, hiddenUnits: 16, learningRate: 0.01, earlyStoppingPatience: 0
  })
  const result = trainTinyModelSync({ training, validation: [], settings })
  const prior = legacyPrediction(result, 'tenBand', 'standard', 'smart')
  const preamp = prior[targetNames.indexOf('preampDB')]
  const lowBand = prior[targetNames.indexOf('tenBand.gains.0')]
  // Legacy population: preamp -5.5, band0 -3. Single account: preamp -9.5, band0 -2.
  assert.ok(preamp > -7.6 && preamp < -3.5, `prior preamp ${preamp} should stay near the population -5.5`)
  assert.ok(lowBand < -2.4, `prior band0 ${lowBand} should follow the population tilt (-3)`)
  assert.equal(result.supervisedTotalWeight, 48)
  assert.ok(Math.abs(result.legacyTotalWeight - 48) < 1e-9)
})

test('32-band prior keeps its curve when every complete sample is 10-band', () => {
  const training = productionShapedExamples({
    completeCount: 40,
    legacyPerBranch: [300, 40, 40, 16]
  })
  const settings = require('./audio-tuning-training').normalizeSettings({
    epochs: 30, hiddenUnits: 16, learningRate: 0.01, earlyStoppingPatience: 0
  })
  const result = trainTinyModelSync({ training, validation: [], settings })
  // Output scale for the 32-band head must come from the legacy targets, not
  // from a 0.001 floor that clips every legacy 32-band target to ±8.
  const scale32 = result.outputNormalization.standardDeviation[targetNames.indexOf('thirtyTwoBand.gains.31')]
  assert.ok(scale32 > 1, `32-band output scale ${scale32}`)
  const prior = legacyPrediction(result, 'thirtyTwoBand', 'standard')
  const first = prior[targetNames.indexOf('thirtyTwoBand.gains.0')]
  const last = prior[targetNames.indexOf('thirtyTwoBand.gains.31')]
  assert.ok(last - first > 3, `32-band prior tilt ${first} → ${last} should not be flat`)
  assert.ok(first < -1.5 && last > 1.5, `32-band prior ends ${first}/${last}`)
  // Never-observed conditional inputs must not be normalised into the ±8 clip.
  const std32 = result.inputNormalization.standardDeviation[featureNames.indexOf('thirtyTwoBand.bandEnergyDB.5')]
  assert.ok(std32 >= 5, `32-band input scale ${std32} should borrow the 10-band energy family`)
  assert.equal(result.inputNormalization.mean[featureNames.indexOf('thirtyTwoBand.bandEnergyDB.5')], 0)
})

test('legacy conditioning respects the plan intensity and zeroes the inactive branch', () => {
  const training = productionShapedExamples({ completeCount: 12, legacyPerBranch: [8, 8, 8, 8] })
  const settings = require('./audio-tuning-training').normalizeSettings({ epochs: 1, hiddenUnits: 4 })
  const result = trainTinyModelSync({ training, validation: [], settings })
  const smart = legacyPrediction(result, 'thirtyTwoBand', 'standard', 'smart')
  const strong = legacyPrediction(result, 'thirtyTwoBand', 'standard', 'strong')
  assert.equal(smart.length, targetNames.length)
  assert.equal(strong.length, targetNames.length)
  assert.ok(result.inputNormalization.standardDeviation.every((value) => value > 0))
})

test('worker-thread training reports progress and honours cancellation', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-audio-training-worker-'))
  try {
    const snapshots = Array.from({ length: 12 }, (_, index) => {
      const id = `worker-${index}`
      const value = sample(id)
      return {
        aiEqualizer: {
          cachedProposals: {},
          savedProposals: { [value.songIdentifier]: [{ id, proposal: value.target }] },
          trainingSamples: { [id]: value }
        }
      }
    })
    const cloudDatabasePath = createCoveredCloudDatabase(directory, snapshots, 'worker')
    const service = createAudioTuningTrainingService({
      directory: path.join(directory, 'training'),
      cloudDatabasePath,
      coreMLExporter: fakeCoreMLExporter,
      logger: { error() {} }
    })
    service.updateSettings({ epochs: 200, hiddenUnits: 32, minimumSamples: 4, earlyStoppingPatience: 0 })
    const job = service.startTraining('full-admin')
    let state = service.status()
    for (let attempt = 0; attempt < 300 && (state.currentJob?.epoch ?? 0) < 2; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.ok(state.currentJob.epoch >= 2, 'progress should arrive from the worker')
    service.cancelTraining(job.id)
    for (let attempt = 0; attempt < 300 && state.currentJob?.isActive; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.equal(state.currentJob.state, 'cancelled')
    assert.equal(state.currentModel, null)
    service.close()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

test('every management route requires training.manage', () => {
  const registrations = []
  const app = {
    get(pathname, ...handlers) { registrations.push({ pathname, handlers }) },
    put(pathname, ...handlers) { registrations.push({ pathname, handlers }) },
    post(pathname, ...handlers) { registrations.push({ pathname, handlers }) }
  }
  const authMiddleware = (_req, _res, next) => next()
  const requestedPermissions = []
  const permissionMiddleware = (_req, _res, next) => next()
  installAudioTuningTrainingRoutes({
    app,
    service: {},
    authMiddleware,
    authorize(permission) {
      requestedPermissions.push(permission)
      return permissionMiddleware
    }
  })
  assert.equal(registrations.length, 8)
  assert.deepEqual(requestedPermissions, ['training.manage'])
  registrations.forEach(({ handlers }) => {
    assert.strictEqual(handlers[0], authMiddleware)
    assert.strictEqual(handlers[1], permissionMiddleware)
  })
})


test('training completes with only 10-band profiles and keeps absent 32-band outputs neutral', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-ten-band-training-'))
  let service
  try {
    const snapshots = Array.from({ length: 8 }, (_, i) => {
      const value = sample(`ten-only-${i}`)
      value.target.tuningProfile = i % 2 === 0 ? 'standard' : 'monoSpatialEnhancement'
      return { aiEqualizer: { cachedProposals: {},
        savedProposals: { [value.songIdentifier]: [{ id: value.id, proposal: value.target }] },
        trainingSamples: { [value.id]: value } } }
    })
    service = createAudioTuningTrainingService({ directory: path.join(directory, 'training'),
      cloudDatabasePath: createCloudDatabase(directory, snapshots), coreMLExporter: fakeCoreMLExporter, logger: { error() {} } })
    service.updateSettings({ epochs: 1, hiddenUnits: 4, minimumSamples: 4 })
    service.startTraining('fixture-admin')
    let state = service.status()
    for (let i = 0; i < 300 && state.currentJob?.isActive; i++) {
      await new Promise(resolve => setTimeout(resolve, 10))
      state = service.status()
    }
    assert.equal(state.currentJob.state, 'completed', state.currentJob.errorMessage)
    assert.equal(state.currentModel.metrics.thirtyTwoBandTrainingSamples, 0)
    assert.equal(state.currentModel.metrics.confidenceCalibration.branches['thirtyTwoBand:standard'].radiusDB, null)
    const artifact = service.modelArtifact(state.currentModel.id).artifact
    for (let i = 10; i < 42; i++) {
      assert.ok(artifact.outputHeadWeights[i].every(value => value === 0))
      assert.equal(artifact.outputHeadBias[i], 0)
    }
  } finally {
    service?.close()
    fs.rmSync(directory, { recursive: true, force: true })
  }
})
