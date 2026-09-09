const RELEASE_NOTES_VERSION = 2
const BRANCHES = [
  ['tenBand:standard', '10 段标准调音', '根据当前歌曲的声音特征调整频段平衡。'],
  ['tenBand:monoSpatialEnhancement', '10 段空间调音', '根据歌曲特征生成空间模式下的音色与声场方案。'],
  ['thirtyTwoBand:standard', '32 段标准调音', '使用更细的频段划分，按歌曲特征生成频段调整方案。'],
  ['thirtyTwoBand:monoSpatialEnhancement', '32 段空间调音', '结合精细频段调整与空间模式，生成对应的音色和声场方案。']
]

function recordedNumber(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0
}

function calibrationEvidence(calibration, key) {
  const branch = calibration?.branches?.[key]
  if (calibration?.schemaVersion !== 1 || calibration.method !== 'split-conformal-track-max-v1'
    || calibration.scope !== 'graphic-eq-reference' || calibration.coverage !== 0.9
    || !Number.isInteger(calibration.minimumTracks) || calibration.minimumTracks < 32
    || !Number.isInteger(calibration.trainingTracks) || calibration.trainingTracks <= 0
    || !Number.isInteger(calibration.calibrationTracks) || calibration.calibrationTracks < branch?.tracks
    || branch?.status !== 'calibrated' || (branch.unresolvedTrackSamples ?? calibration.unresolvedTrackSamples ?? 0) !== 0
    || !Number.isInteger(branch.tracks) || branch.tracks < calibration.minimumTracks
    || !Number.isInteger(branch.samples) || branch.samples < branch.tracks
    || branch.quantileRank !== Math.ceil((branch.tracks + 1) * 0.9) || branch.quantileRank > branch.tracks
    || !recordedNumber(branch.radiusDB) || !recordedNumber(branch.trackCorrectionStrength)
    || branch.trackCorrectionStrength > 1) return null
  return branch
}


function branchCapability(model, key) {
  if (key.startsWith('thirtyTwoBand:') && model?.featureSchemaVersion < 6) return false
  const metrics = model?.metrics || {}
  if (calibrationEvidence(metrics.confidenceCalibration, key)) return true
  const training = metrics.completeBranchTrainingSamples?.[key]
  const validation = metrics.completeBranchValidationSamples?.[key] ?? metrics.branchValidation?.[key]?.samples
  if (!recordedNumber(training) || !recordedNumber(validation)) return null
  if (training > 0 && validation > 0) return true
  return training === 0 && validation === 0 ? false : null
}

function contextCapability(model, key, minimumSchema) {
  if (!recordedNumber(model?.featureSchemaVersion)) return null
  if (model.featureSchemaVersion < minimumSchema) return false
  const training = model.metrics?.[`${key}TrainingSamples`]
  const validation = model.metrics?.[`${key}ValidationSamples`]
  // Match the on-device gates for embedded preferences and detailed device context.
  if ((recordedNumber(training) ? training : 0) + (recordedNumber(validation) ? validation : 0) >= 8) return true
  return recordedNumber(training) && recordedNumber(validation) ? false : null
}

function capabilities(model) {
  const entries = BRANCHES.map(([key, title, description]) => ({
    key, title, description, available: branchCapability(model, key)
  }))
  entries.push({ key: 'learning', title: '个性化听感',
    description: '将已学习的听感偏好纳入调音，按个人偏好生成方案。',
    available: contextCapability(model, 'learningConditioned', 4) })
  entries.push({ key: 'device', title: '设备适配',
    description: '结合当前输出设备的声学信息生成调音方案。',
    available: contextCapability(model, 'deviceConditioned', 5) })
  for (const [key, title] of BRANCHES) {
    const calibration = model?.metrics?.confidenceCalibration
    entries.push({ key: `confidence:${key}`, title: `${title}的可靠性评估`,
      description: '为调音结果提供可信度参考，帮助判断建议的参考价值。',
      available: calibration ? Boolean(calibrationEvidence(calibration, key)) : null })
  }
  return entries
}

function generateReleaseNotes(model, previous) {
  const baseline = new Map(capabilities(previous).map(entry => [entry.key, entry.available]))
  const current = capabilities(model).filter(entry => entry.available === true)
  if (!current.length) {
    const summary = '本次更新调音模型，沿用现有调音功能。'
    return { summary, notes: `• ${summary}` }
  }
  const added = current.filter(entry => baseline.get(entry.key) === false)
  const summary = added.length
    ? `新增${added.map(entry => entry.title).join('、')}。`
    : `${previous ? '本次更新' : '提供'}${current.map(entry => entry.title).join('、')}。`
  const notes = [...added, ...current.filter(entry => !added.includes(entry))].map(entry => {
    const before = baseline.get(entry.key)
    const action = before === false ? '新增' : before === true ? '更新' : '支持'
    const separator = /^\d/.test(entry.title) ? ' ' : ''
    return `• ${action}${separator}${entry.title}：${entry.description}`
  }).join('\n')
  return { summary, notes }
}

module.exports = { RELEASE_NOTES_VERSION, generateReleaseNotes }
