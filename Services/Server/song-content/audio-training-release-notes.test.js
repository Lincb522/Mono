const test = require('node:test')
const assert = require('node:assert/strict')
const { generateReleaseNotes } = require('./audio-training-release-notes')

function model() {
  return { version: 'mono-resonance-s2-schema7-current', featureSchemaVersion: 7,
    targetSchemaVersion: 4, sampleCount: 120,
    metrics: { trainingSamples: 80, validationSamples: 20, epochsRun: 10,
      completeBranchTrainingSamples: { 'tenBand:standard': 40, 'tenBand:monoSpatialEnhancement': 20,
        'thirtyTwoBand:standard': 0, 'thirtyTwoBand:monoSpatialEnhancement': 0 },
      completeBranchValidationSamples: { 'tenBand:standard': 10, 'tenBand:monoSpatialEnhancement': 10,
        'thirtyTwoBand:standard': 0, 'thirtyTwoBand:monoSpatialEnhancement': 0 },
      learningConditionedTrainingSamples: 8, learningConditionedValidationSamples: 0,
      deviceConditionedTrainingSamples: 8, deviceConditionedValidationSamples: 0 } }
}

const internalReport = /样本|训练|选模|账户|误差|覆盖率|百分比|dB|schema|NaN|undefined|null/

test('release notes describe tuning capabilities without exposing the training report', () => {
  const current = model()
  const previous = model()
  previous.sampleCount = 100
  const notes = generateReleaseNotes(current, previous)
  for (const text of ['10 段标准调音', '10 段空间调音', '个性化听感', '设备适配']) {
    assert.ok(notes.notes.includes(text), text)
  }
  assert.doesNotMatch(notes.summary + notes.notes, internalReport)
  assert.doesNotMatch(notes.notes, /32 段|音质提升|修复卡音|更好听|更清晰|更稳定/)
})

test('new personalization and optional 32-band capabilities are described only when available', () => {
  const previous = model()
  previous.metrics.learningConditionedTrainingSamples = 7
  const current = model()
  current.metrics.completeBranchTrainingSamples['thirtyTwoBand:standard'] = 40
  current.metrics.completeBranchValidationSamples['thirtyTwoBand:standard'] = 10
  const notes = generateReleaseNotes(current, previous)
  assert.match(notes.notes, /新增个性化听感/)
  assert.match(notes.notes, /新增 32 段标准调音/)
  assert.doesNotMatch(notes.notes, /32 段空间调音/)
  assert.doesNotMatch(notes.summary + notes.notes, internalReport)
})

test('context capabilities follow the runtime sample thresholds and model schema', () => {
  const current = model()
  current.metrics.learningConditionedTrainingSamples = 7
  current.metrics.deviceConditionedTrainingSamples = 0
  current.metrics.deviceConditionedValidationSamples = 7
  assert.doesNotMatch(generateReleaseNotes(current).notes, /个性化听感|设备适配/)
  current.metrics.deviceConditionedValidationSamples = 8
  assert.match(generateReleaseNotes(current).notes, /设备适配/)
  current.featureSchemaVersion = 3
  current.metrics.learningConditionedTrainingSamples = 100
  assert.doesNotMatch(generateReleaseNotes(current).notes, /个性化听感|设备适配/)
})

test('a few unvalidated 32-band examples do not become a claim of improved 32-band tuning', () => {
  const current = model()
  current.metrics.completeBranchTrainingSamples['thirtyTwoBand:standard'] = 2
  const notes = generateReleaseNotes(current)
  assert.match(notes.notes, /10 段标准调音/)
  assert.match(notes.notes, /10 段空间调音/)
  assert.doesNotMatch(notes.notes, /32 段|未校准/)
})

test('calibrated confidence is explained as a user capability, independently for each branch', () => {
  const current = model()
  current.metrics.confidenceCalibration = { schemaVersion: 1, method: 'split-conformal-track-max-v1',
    scope: 'graphic-eq-reference', coverage: 0.9, minimumTracks: 32, trainingTracks: 64, calibrationTracks: 40,
    branches: { 'tenBand:standard': { status: 'calibrated', samples: 40, tracks: 40,
      quantileRank: 37, radiusDB: 0.8, trackCorrectionStrength: 1 } } }
  const previous = model()
  previous.metrics.confidenceCalibration = { branches: {} }
  const notes = generateReleaseNotes(current, previous)
  assert.match(notes.notes, /新增 10 段标准调音的可靠性评估/)
  assert.doesNotMatch(notes.summary + notes.notes, internalReport)
  current.metrics.confidenceCalibration.branches['tenBand:standard'].radiusDB = null
  assert.doesNotMatch(generateReleaseNotes(current, previous).notes, /可靠性评估/)
})

test('missing evidence does not invent improvements, new capabilities, or a training report', () => {
  const notes = generateReleaseNotes({ version: 'mono-resonance-s2-empty' })
  assert.match(notes.notes, /调音模型/)
  assert.doesNotMatch(notes.summary + notes.notes, internalReport)
  assert.doesNotMatch(notes.notes, /新增|提升|改善|优化|标准调音|空间调音|个性化|设备适配/)
  assert.doesNotMatch(generateReleaseNotes(model(), {}).notes, /新增/)
})

test('sample growth and non-comparable validation scores do not turn into claims of audible improvement', () => {
  const current = model()
  const previous = model()
  previous.sampleCount = 10
  current.metrics.branchValidation = { 'tenBand:standard': { samples: 10, eqMAEDB: 0.1, improvesPrior: true } }
  previous.metrics.branchValidation = { 'tenBand:standard': { samples: 100, eqMAEDB: 0.9 } }
  assert.deepEqual(generateReleaseNotes(current, previous), generateReleaseNotes(model(), model()))
  assert.deepEqual(generateReleaseNotes(current, previous), generateReleaseNotes(current, previous))
})
