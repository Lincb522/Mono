const test = require('node:test')
const assert = require('node:assert/strict')
const t = require('./audio-tuning-training')
const branches = ['tenBand:standard', 'tenBand:monoSpatialEnhancement',
  'thirtyTwoBand:standard', 'thirtyTwoBand:monoSpatialEnhancement']
function item(id, branch, error = 0) {
  const [graphicEQMode, tuningProfile] = branch.split(':')
  const y = t.targetNames.map(() => 0)
  const start = graphicEQMode === 'tenBand' ? 0 : 10
  const count = graphicEQMode === 'tenBand' ? 10 : 32
  y[start + count - 1] = error
  return { id, trackGroup: id, accountId: `account-${Number(id.match(/\d+/)?.[0] || 0) % 3}`,
    graphicEQMode, tuningProfile, x: t.featureNames.map(() => 0), y,
    targetMask: t.targetNames.map((_, i) => i >= start && i < start + count ? 1 : 0), sampleWeight: 1 }
}
function data() {
  return {
    training: branches.flatMap(b => Array.from({ length: 64 }, (_, i) => item(`fit-${i}-${b}`, b))),
    validation: branches.map(b => item(`selection-${b}`, b)),
    calibration: branches.flatMap(b => Array.from({ length: 40 }, (_, i) => item(`held-${i}-${b}`, b, (i + 1) / 100))),
    settings: t.normalizeSettings({ epochs: 1, hiddenUnits: 4, intentUnits: 3, earlyStoppingPatience: 0 })
  }
}
test('calibration split isolates songs including historical targets and retains native branches', () => {
  const examples = Array.from({length: 160}, (_, i) => branches.map(b => item(`song-${i}`, b))).flat()
  const old = examples.map(v => ({ ...v, id: `old-${v.id}`, x: null }))
  const split = t.splitCalibrationExamples([...examples, ...old], 40)
  const sets = ['training', 'validation', 'calibration'].map(k => new Set(split[k].map(v => v.trackGroup)))
  assert.equal(sets[0].size, 96)
  assert.equal(sets[1].size, 32)
  assert.equal(sets[2].size, 32)
  for (let i = 0; i < sets.length; i++) for (let j = i + 1; j < sets.length; j++) {
    assert.ok([...sets[i]].every(k => !sets[j].has(k)))
  }
  assert.equal(split.calibration.filter(v => v.x === null).length, 0)
  assert.equal(new Set(split.training.map(v => `${v.graphicEQMode}:${v.tuningProfile}`)).size, 4)
})
test('calibration uses finite-sample rank and the last native 32-band target; weights never see calibration targets', () => {
  const d = data()
  const model = t.trainTinyModelSync(d)
  for (const b of branches) {
    const c = model.confidenceCalibration.branches[b]
    assert.equal(c.tracks, 40)
    assert.equal(c.quantileRank, 37)
    assert.ok(Math.abs(c.radiusDB - 0.371) < 1e-10, JSON.stringify(c))
  }
  const changed = t.trainTinyModelSync({ ...d, calibration: d.calibration.map(v => ({ ...v, y: v.y.map(x => x * 3) })) })
  for (const k of ['hiddenWeights', 'outputHeadWeights', 'outputHeadBias', 'inputNormalization', 'outputNormalization']) {
    assert.deepEqual(model[k], changed[k])
  }
  assert.ok(Math.abs(changed.confidenceCalibration.branches[branches[3]].radiusDB - 1.111) < 1e-10)
})
test('paired contexts and repeated captures get one worst-error vote per song', () => {
  const d = data()
  d.calibration = d.calibration.map(v => ({ ...v, populationPair: { x: v.x, y: v.y.map(x => x * 2), targetMask: v.targetMask } }))
  d.calibration.push(...d.calibration.slice(0, 10))
  const model = t.trainTinyModelSync(d)
  const c = model.confidenceCalibration.branches[branches[0]]
  assert.equal(c.tracks, 40)
  assert.ok(Math.abs(c.radiusDB - 0.741) < 1e-10)
})
test('10-band calibration remains valid without 32-band evidence and calibration never overlaps training', () => {
  const d = data()
  assert.throws(() => t.trainTinyModelSync({ ...d, calibration: [d.training[0]] }), { code: 'CALIBRATION_DATA_LEAKAGE' })
  const model = t.trainTinyModelSync({ ...d, calibration: d.calibration.filter(v => v.graphicEQMode === 'tenBand') })
  assert.equal(model.confidenceCalibration.branches[branches[2]].radiusDB, null)
  const only32 = t.trainTinyModelSync({ ...d, calibration: d.calibration.filter(v => v.graphicEQMode === 'thirtyTwoBand') })
  assert.equal(only32.confidenceCalibration.branches[branches[0]].radiusDB, null)
  assert.equal(only32.confidenceCalibration.branches[branches[2]].status, 'calibrated')
})

test('unknown song identity cannot supply a claim of independent calibration', () => {
  const d = data()
  d.training[0].trackGroup = 'proposal:unknown-song'
  const model = t.trainTinyModelSync(d)
  assert.equal(model.confidenceCalibration.unresolvedTrackSamples, 1)
  assert.equal(model.confidenceCalibration.branches[branches[0]].status, 'unresolved_track_identity')
  assert.equal(model.confidenceCalibration.branches[branches[0]].radiusDB, null)
})


test('one calibrated 10-band branch remains valid and later 32-band evidence is included independently', () => {
  const d = data()
  const first = t.trainTinyModelSync({ ...d, calibration: d.calibration.filter(v => v.graphicEQMode === 'tenBand' && v.tuningProfile === 'standard') })
  assert.equal(first.confidenceCalibration.branches[branches[0]].status, 'calibrated')
  assert.equal(first.confidenceCalibration.branches[branches[1]].status, 'insufficient_calibration_tracks')
  const updated = t.trainTinyModelSync(d)
  for (const b of branches) assert.equal(updated.confidenceCalibration.branches[b].status, 'calibrated')
})

test('unidentified recordings are omitted before fitting and no longer invalidate identified 10-band calibration', () => {
  const examples = Array.from({length: 400}, (_, i) => item(`song-${i}`, branches[0]))
  const unknown = { ...item('unknown', branches[3]), trackGroup: 'proposal:unknown-song', x: null }
  const split = t.splitCalibrationExamples([...examples, unknown], 40)
  assert.equal(split.excludedUnresolvedTrackSamples, 1)
  for (const part of ['training', 'validation', 'calibration']) {
    assert.ok(split[part].every(v => v.trackGroup !== unknown.trackGroup))
  }
  const model = t.trainTinyModelSync({ ...split, settings: data().settings })
  assert.equal(model.confidenceCalibration.branches[branches[0]].status, 'calibrated')
  assert.equal(model.confidenceCalibration.unresolvedTrackSamples, 0)
})

test('an unidentified held-out 32-band recording affects only its own branch', () => {
  const d = data()
  const target = d.calibration.find(v => v.graphicEQMode === 'thirtyTwoBand')
  target.trackGroup = 'proposal:unknown-held-out'
  const model = t.trainTinyModelSync(d)
  assert.equal(model.confidenceCalibration.unresolvedTrackSamples, 1)
  assert.equal(model.confidenceCalibration.branches[branches[0]].unresolvedTrackSamples, 0)
  assert.equal(model.confidenceCalibration.branches[branches[0]].status, 'calibrated')
  assert.equal(model.confidenceCalibration.branches[branches[2]].status, 'unresolved_track_identity')
})
