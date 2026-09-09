const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const crypto = require('node:crypto')
const { DatabaseSync } = require('node:sqlite')
const { installAIRemoteConfigRoutes } = require('./ai-remote-config')
const { createAudioTuningTrainingService, installAudioTuningTrainingRoutes } = require('../song-content/audio-tuning-training')

function fixture() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'mono-s2-distribution-'))
  const service = createAudioTuningTrainingService({
    directory, coreMLExporter() { throw new Error('Public downloads must not trigger model export') },
    logger: { error() {} }
  })
  const database = new DatabaseSync(service.databasePath)
  const bytes = Buffer.alloc(512, 31)
  const sha = crypto.createHash('sha256').update(bytes).digest('hex')
  const metrics = {
    completeTrainingSamples: 60, completeValidationSamples: 4,
    learningConditionedTrainingSamples: 8, deviceConditionedTrainingSamples: 10,
    completeAccountCount: 3, completeBranchTrainingSamples: { 'tenBand:standard': 20 },
    completeBranchValidationSamples: { 'tenBand:standard': 4 },
    completeBranchAccounts: { 'tenBand:standard': 3 }, qualityWarnings: []
  }
  const confidenceCalibration = {
    schemaVersion: 1, method: 'split-conformal-track-max-v1', scope: 'graphic-eq-reference',
    coverage: 0.9, minimumTracks: 32, trainingTracks: 64, selectionTracks: 16, calibrationTracks: 40,
    branches: Object.fromEntries(['tenBand:standard', 'tenBand:monoSpatialEnhancement',
      'thirtyTwoBand:standard', 'thirtyTwoBand:monoSpatialEnhancement'].map(branch => [branch, {
        status: 'calibrated', samples: 40, tracks: 40, quantileRank: 37, radiusDB: 0.8, trackCorrectionStrength: 1
      }]))
  }
  for (const [id, schema, target] of [['first', 7, 4], ['second', 7, 4], ['draft', 7, 4], ['s1', 6, 3]]) {
    const version = `mono-resonance-${id === 's1' ? 's1' : 's2'}-schema${schema}-${id}`
    fs.writeFileSync(path.join(directory, 'models', `${id}.mlmodel`), bytes)
    database.prepare(`INSERT INTO audio_training_models
      (id, version, feature_schema_version, target_schema_version, artifact_json, metrics_json,
       dataset_fingerprint, sample_count, created_at) VALUES (?, ?, ?, ?, ?, ?, 'fixture', 64, ?)`)
      .run(id, version, schema, target, JSON.stringify({ confidenceCalibration }), JSON.stringify({ ...metrics, confidenceCalibration }), new Date().toISOString())
    database.prepare(`INSERT INTO audio_training_model_artifacts
      (model_id, format, relative_path, sha256, byte_count, created_at) VALUES (?, ?, ?, ?, ?, ?)`)
      .run(id, 'coreml-neuralnetwork-v2', `${id}.mlmodel`, sha, bytes.length, new Date().toISOString())
  }
  database.close()
  const registrations = []
  const app = { locals: {} }
  for (const method of ['get', 'post', 'put']) {
    app[method] = (pathname, ...handlers) => registrations.push({ method, pathname, handlers })
  }
  const data = {}
  const auth = (req, res, next) => req.headers['x-admin-token']
    ? next() : res.status(401).json({ error: 'unauthorized' })
  const authorize = () => (req, res, next) => req.headers['x-admin-token'] === 'fixture-full'
    ? next() : res.status(403).json({ error: 'full access required' })
  const resolvePublicToken = (req, res) => {
    if (req.headers['x-api-token'] !== 'fixture-user' || req.headers['x-device-id'] !== 'fixture-device') {
      res.status(401).json({ error: 'unauthorized' })
      return null
    }
    return { data }
  }
  app.locals.audioTrainingDistribution = { service, authorize: authorize('training.manage') }
  installAIRemoteConfigRoutes({ app, saveData() {}, authMiddleware: auth, resolvePublicToken })
  installAudioTuningTrainingRoutes({ app, service, authMiddleware: auth, authorize, resolvePublicToken, logger: { error() {} } })

  async function request(method, pathname, body, headers = {}) {
    let match
    const route = registrations.find((entry) => {
      if (entry.method !== method.toLowerCase()) return false
      match = pathname.match(new RegExp(`^${entry.pathname.replace(/:[^/]+/g, '([^/]+)')}$`))
      return match
    })
    assert.ok(route, `route exists: ${method} ${pathname}`)
    const params = Object.fromEntries((route.pathname.match(/:[^/]+/g) || []).map((name, i) => [name.slice(1), match[i + 1]]))
    const req = { appData: data, body, headers, params }
    const response = { statusCode: 200, headers: {} }
    const res = {
      status(code) { response.statusCode = code; return res },
      json(value) { response.body = value; return res },
      set(name, value) { response.headers[name.toLowerCase()] = value; return res },
      setHeader(name, value) { res.set(name, value) },
      end() {},
      download(file, name) { response.bytes = fs.readFileSync(file); response.fileName = name }
    }
    async function run(index) {
      let next
      await route.handlers[index]?.(req, res, () => { next = run(index + 1) })
      if (next) await next
    }
    await run(0)
    return response
  }
  return {
    service, directory, bytes, data, request, app,
    close() { service.close(); fs.rmSync(directory, { recursive: true, force: true }) }
  }
}

const admin = { 'x-admin-token': 'fixture-full' }
const user = { 'x-api-token': 'fixture-user', 'x-device-id': 'fixture-device' }
function configuration(modelID = 'first') {
  return {
    enabled: true, resonance: { enabled: true, modelID },
    configuration: { wireProtocol: 'openAICompatible', baseURL: '', model: '' }, apiKey: ''
  }
}

test('published S2 selection reaches ordinary users through authenticated configuration and download routes', async () => {
  const f = fixture()
  try {
    assert.deepEqual(f.service.publishedModels(), [])
    const published = await f.request('POST', '/api/audio-training/models/first/publish', { confirmed: true }, admin)
    assert.equal(published.statusCode, 200)
    await f.service.publishModel('second', 'fixture-full')
    await f.service.publishModel('s1', 'fixture-full')
    const list = await f.request('GET', '/api/audio-training/models', null, admin)
    assert.deepEqual(new Set(list.body.models.map((model) => model.id)), new Set(['first', 'second']))
    assert.equal(list.body.models.find((model) => model.id === 'first').completeBranchSampleCounts['tenBand:standard'], 24)
    const saved = await f.request('PUT', '/api/ai/config', configuration(), admin)
    assert.equal(saved.statusCode, 200)
    assert.equal(saved.body.resonance.model.id, 'first')
    const publicConfig = await f.request('GET', '/api/public/ai/config', null, user)
    const expectedPublic = structuredClone(saved.body.resonance)
    assert.deepEqual(publicConfig.body.resonance, expectedPublic)
    assert.equal(publicConfig.body.resonance.model.artifact, undefined)
    assert.equal(publicConfig.body.resonance.model.filePath, undefined)
    const download = await f.request('GET', '/api/public/audio-training/models/first/coreml', null, user)
    assert.equal(download.statusCode, 200)
    assert.deepEqual(download.bytes, f.bytes)
    assert.equal(download.headers['x-mono-model-sha256'], saved.body.resonance.model.sha256)
    assert.equal(download.headers['x-mono-feature-schema'], '7')
    assert.equal(download.headers['x-mono-target-schema'], '4')
    const unchanged = await f.request('GET', '/api/public/ai/config', null, { ...user, 'if-none-match': publicConfig.headers.etag })
    assert.equal(unchanged.statusCode, 304)
  } finally { f.close() }
})

test('ordinary and restricted users cannot manage or download unselected models', async () => {
  const f = fixture()
  try {
    await f.service.publishModel('first', 'fixture-full')
    await f.service.publishModel('second', 'fixture-full')
    for (const headers of [user, { 'x-admin-token': 'fixture-content-only' }]) {
      assert.ok((await f.request('GET', '/api/audio-training/models', null, headers)).statusCode >= 400)
      assert.ok((await f.request('PUT', '/api/ai/config', configuration(), headers)).statusCode >= 400)
    }
    assert.equal((await f.request('PUT', '/api/ai/config', configuration('draft'), admin)).statusCode, 400)
    assert.equal((await f.request('PUT', '/api/ai/config', configuration('missing'), admin)).statusCode, 400)
    await f.service.publishModel('s1', 'fixture-full')
    assert.equal((await f.request('PUT', '/api/ai/config', configuration('s1'), admin)).statusCode, 400)
    await f.request('PUT', '/api/ai/config', configuration(), admin)
    assert.equal((await f.request('GET', '/api/public/audio-training/models/first/coreml')).statusCode, 401)
    assert.equal((await f.request('GET', '/api/public/audio-training/models/second/coreml', null, user)).statusCode, 403)
    assert.equal((await f.request('GET', '/api/public/audio-training/models/draft/coreml', null, user)).statusCode, 403)
    const tampered = configuration()
    tampered.resonance.model = { id: 'draft', sha256: 'untrusted' }
    assert.equal((await f.request('PUT', '/api/ai/config', tampered, admin)).body.resonance.model.id, 'first')
  } finally { f.close() }
})

test('switching, disabling, stale revisions, and legacy updates preserve distribution contracts', async () => {
  const f = fixture()
  try {
    await f.service.publishModel('first', 'fixture-full')
    await f.service.publishModel('second', 'fixture-full')
    const first = await f.request('PUT', '/api/ai/config', configuration(), admin)
    await f.request('PUT', '/api/ai/config', { ...configuration('second'), expectedRevision: first.body.revision }, admin)
    assert.equal((await f.request('PUT', '/api/ai/config', { ...configuration(), expectedRevision: first.body.revision }, admin)).statusCode, 409)
    assert.equal((await f.request('GET', '/api/public/audio-training/models/first/coreml', null, user)).statusCode, 403)
    const legacy = configuration(); delete legacy.resonance
    assert.equal((await f.request('PUT', '/api/ai/config', legacy, admin)).body.resonance.model.id, 'second')
    const disabled = { ...configuration('second'), enabled: false }
    await f.request('PUT', '/api/ai/config', disabled, admin)
    assert.equal((await f.request('GET', '/api/public/audio-training/models/second/coreml', null, user)).statusCode, 403)
    disabled.resonance.enabled = false
    assert.equal((await f.request('PUT', '/api/ai/config', disabled, admin)).statusCode, 200)
  } finally { f.close() }
})

test('corrupt published files fail without exporting or sending unverified bytes', async () => {
  const f = fixture()
  try {
    await f.service.publishModel('first', 'fixture-full')
    await f.request('PUT', '/api/ai/config', configuration(), admin)
    fs.writeFileSync(path.join(f.directory, 'models', 'first.mlmodel'), Buffer.alloc(512, 42))
    const response = await f.request('GET', '/api/public/audio-training/models/first/coreml', null, user)
    assert.equal(response.statusCode, 503)
    assert.equal(response.bytes, undefined)
    assert.equal((await f.request('PUT', '/api/ai/config', configuration(), admin)).statusCode, 400)
  } finally { f.close() }
})

test('existing publication migrates into the selectable catalog on service restart', async () => {
  const f = fixture()
  let restarted
  try {
    await f.service.publishModel('first', 'fixture-full')
    f.service.close()
    const database = new DatabaseSync(path.join(f.directory, 'audio-training.sqlite'))
    database.exec('DROP TABLE audio_training_published_models')
    database.close()
    restarted = createAudioTuningTrainingService({ directory: f.directory, logger: { error() {} } })
    assert.deepEqual(restarted.publishedModels().map((model) => model.id), ['first'])
    assert.equal(restarted.publishedCoreMLArtifact('first').sha256, crypto.createHash('sha256').update(f.bytes).digest('hex'))
  } finally {
    restarted?.close()
    fs.rmSync(f.directory, { recursive: true, force: true })
  }
})

test('uncalibrated models can publish, be selected, and reach users without fabricated confidence', async () => {
  const f = fixture()
  try {
    await f.service.publishModel('first', 'fixture-full')
    const database = new DatabaseSync(f.service.databasePath)
    database.prepare("UPDATE audio_training_models SET artifact_json = '{}' WHERE id = 'second'").run()
    database.close()
    const response = await f.request('POST', '/api/audio-training/models/second/publish', { confirmed: true }, admin)
    assert.equal(response.statusCode, 200)
    assert.equal(response.body.model.id, 'second')
    assert.equal(f.service.publishedModels()[0].id, 'second')
    const saved = await f.request('PUT', '/api/ai/config', configuration('second'), admin)
    assert.equal(saved.statusCode, 200)
    const downloaded = await f.request('GET', '/api/public/audio-training/models/second/coreml', null, user)
    assert.deepEqual(downloaded.bytes, f.bytes)
    assert.equal(f.service.modelArtifact('second').artifact.confidenceCalibration, undefined)
  } finally { f.close() }
})

test('publishing automatically saves notes matching the preview and serves the complete changelog with a readable file name', async () => {
  const f = fixture()
  try {
    const preview = f.service.modelArtifact('first').releasePreview
    const result = await f.request('POST', '/api/audio-training/models/first/publish', { confirmed: true }, admin)
    assert.equal(result.statusCode, 200)
    const release = result.body.model.release
    assert.equal(release.generatedAutomatically, true)
    assert.equal(release.summary, preview.summary)
    assert.equal(release.notes, preview.notes)
    assert.match(release.changelog, /10 段/)
    assert.match(release.changelog, /32 段/)
    assert.equal(release.changelog, release.notes)
    assert.ok(Number.isFinite(Date.parse(release.publishedAt)))
    assert.equal(f.service.status().publishedModel.id, 'first')
    const catalog = await f.request('GET', '/api/audio-training/models', null, admin)
    assert.equal(catalog.headers['cache-control'], 'private, no-store')
    assert.deepEqual(catalog.body.models[0].release, release)
    await f.request('PUT', '/api/ai/config', configuration(), admin)
    const publicConfig = await f.request('GET', '/api/public/ai/config', null, user)
    assert.equal(publicConfig.body.resonance.model.release.notes, release.notes)
    assert.equal(publicConfig.body.resonance.model.release.changelog, release.changelog)
    const download = await f.request('GET', '/api/public/audio-training/models/first/coreml', null, user)
    assert.match(download.fileName, /^Mono-Resonance-S2_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}UTC\.mlmodel$/)
    assert.deepEqual(download.bytes, f.bytes)
    assert.equal(download.fileName, catalog.body.models[0].fileName)
  } finally { f.close() }
})

test('full release notes preserve long paragraphs and trailing lines and invalidate cached user configuration', async () => {
  const f = fixture()
  try {
    await f.service.publishModel('first', 'fixture-full')
    await f.request('PUT', '/api/ai/config', configuration(), admin)
    const notes = ['• ' + '设备适配与个性化听感。'.repeat(60), '', '• 第二项能力', '• 第三项能力', '• 完整日志末行'].join('\n')
    assert.ok(notes.length > 420)
    const database = new DatabaseSync(f.service.databasePath)
    database.prepare('UPDATE audio_training_published_models SET release_notes = ? WHERE model_id = ?').run(notes, 'first')
    database.close()
    const initial = await f.request('GET', '/api/public/ai/config', null, user)
    const release = JSON.parse(JSON.stringify(initial.body)).resonance.model.release
    assert.equal(release.notes, notes)
    assert.equal(release.changelog, notes)
    const catalog = await f.request('GET', '/api/audio-training/models', null, admin)
    assert.equal(catalog.body.models[0].release.changelog, notes)

    const updatedNotes = notes.replace('完整日志末行', '更新后的完整日志末行')
    const updatedDatabase = new DatabaseSync(f.service.databasePath)
    updatedDatabase.prepare('UPDATE audio_training_published_models SET release_notes = ? WHERE model_id = ?').run(updatedNotes, 'first')
    updatedDatabase.close()
    const updated = await f.request('GET', '/api/public/ai/config', null, { ...user, 'if-none-match': initial.headers.etag })
    assert.equal(updated.statusCode, 200)
    assert.notEqual(updated.headers.etag, initial.headers.etag)
    assert.equal(updated.body.revision, initial.body.revision)
    assert.equal(updated.body.resonance.model.release.changelog, updatedNotes)
    const unchanged = await f.request('GET', '/api/public/ai/config', null, { ...user, 'if-none-match': updated.headers.etag })
    assert.equal(unchanged.statusCode, 304)
  } finally { f.close() }
})

test('publication metadata refreshes independently from selected configuration and retains generated content on retry', async () => {
  const f = fixture()
  try {
    await f.service.publishModel('first', 'fixture-full')
    await f.request('PUT', '/api/ai/config', configuration(), admin)
    const database = new DatabaseSync(f.service.databasePath)
    database.prepare("UPDATE audio_training_published_models SET published_at = '2020-01-01T00:00:00.000Z' WHERE model_id = 'first'").run()
    database.close()
    const initial = await f.request('GET', '/api/public/ai/config', null, user)
    await f.service.publishModel('first', 'fixture-full')
    const updated = await f.request('GET', '/api/public/ai/config', null, { ...user, 'if-none-match': initial.headers.etag })
    assert.equal(updated.statusCode, 200)
    assert.equal(updated.body.revision, initial.body.revision)
    assert.notEqual(updated.headers.etag, initial.headers.etag)
    assert.equal(updated.body.resonance.model.release.summary, initial.body.resonance.model.release.summary)
    const adminConfig = await f.request('GET', '/api/ai/config', null, admin)
    assert.ok(adminConfig.body.resonance.model.release.notes.length > 0)
    await f.service.publishModel('second', 'fixture-full')
    assert.equal(f.service.publishedModels()[0].id, 'second')
    const advanced = await f.request('GET', '/api/public/ai/config', null, { ...user, 'if-none-match': updated.headers.etag })
    assert.equal(advanced.statusCode, 200)
    assert.equal(advanced.body.resonance.model.id, 'second')
    const saved = await f.request('PUT', '/api/ai/config', { ...configuration('second'), expectedRevision: updated.body.revision }, admin)
    assert.equal(saved.statusCode, 200)
  } finally { f.close() }
})

test('client-supplied notes cannot override automatically generated facts or prevent an uncalibrated publication', async () => {
  const f = fixture()
  try {
    const database = new DatabaseSync(f.service.databasePath)
    database.prepare("UPDATE audio_training_models SET artifact_json = '{}', metrics_json = '{}' WHERE id = 'second'").run()
    database.close()
    const response = await f.request('POST', '/api/audio-training/models/second/publish', {
      confirmed: true, releaseSummary: '音质提升十倍', releaseNotes: { malformed: true }
    }, admin)
    assert.equal(response.statusCode, 200)
    assert.equal(response.body.model.release.generatedAutomatically, true)
    assert.match(response.body.model.release.summary, /本次更新调音模型/)
    assert.doesNotMatch(response.body.model.release.notes, /音质提升十倍|malformed/)
    assert.equal(f.service.modelArtifact('second').artifact.confidenceCalibration, undefined)
  } finally { f.close() }
})

test('automatically generated notes persist after restart and keep the original comparison when republishing', async () => {
  const f = fixture()
  let restarted
  try {
    const database = new DatabaseSync(f.service.databasePath)
    const metrics = JSON.parse(database.prepare("SELECT metrics_json FROM audio_training_models WHERE id = 'first'").get().metrics_json)
    metrics.learningConditionedTrainingSamples = 0
    metrics.learningConditionedValidationSamples = 0
    database.prepare("UPDATE audio_training_models SET metrics_json = ? WHERE id = 'first'").run(JSON.stringify(metrics))
    database.close()
    await f.service.publishModel('first', 'fixture-full')
    const second = await f.service.publishModel('second', 'fixture-full')
    assert.match(second.release.summary, /新增个性化听感/)
    f.service.close()
    restarted = createAudioTuningTrainingService({ directory: f.directory, logger: { error() {} } })
    assert.equal(restarted.modelArtifact('second').release.notes, second.release.notes)
    await restarted.publishModel('first', 'fixture-old-client')
    const retried = await restarted.publishModel('second', 'fixture-old-client')
    assert.equal(retried.release.notes, second.release.notes)
    assert.equal(retried.release.summary, second.release.summary)
  } finally {
    restarted?.close()
    fs.rmSync(f.directory, { recursive: true, force: true })
  }
})


test('older release reports migrate to user capabilities without republishing, and public caches refresh', async () => {
  const f = fixture()
  let restarted
  try {
    await f.service.publishModel('first', 'fixture-full')
    await f.service.publishModel('second', 'fixture-full')
    await f.request('PUT', '/api/ai/config', configuration(), admin)
    const database = new DatabaseSync(f.service.databasePath)
    database.prepare("UPDATE audio_training_published_models SET release_summary = '方案样本增加 16 条', release_notes = '训练样本：80 条', release_generator_version = 1").run()
    const publications = database.prepare('SELECT model_id, published_at FROM audio_training_published_models ORDER BY model_id').all()
    const publication = database.prepare('SELECT * FROM audio_training_model_publication').get()
    const artifacts = database.prepare('SELECT * FROM audio_training_model_artifacts ORDER BY model_id').all()
    const models = database.prepare('SELECT * FROM audio_training_models ORDER BY id').all()
    database.close()
    const old = await f.request('GET', '/api/public/ai/config', null, user)
    assert.match(old.body.resonance.model.release.summary, /样本增加/)
    f.service.close()
    restarted = createAudioTuningTrainingService({ directory: f.directory, logger: { error() {} } })
    f.app.locals.audioTrainingDistribution.service = restarted
    const current = await f.request('GET', '/api/public/ai/config', null, { ...user, 'if-none-match': old.headers.etag })
    assert.equal(current.statusCode, 200)
    assert.equal(current.body.revision, old.body.revision)
    assert.notEqual(current.headers.etag, old.headers.etag)
    assert.equal(current.body.resonance.model.id, old.body.resonance.model.id)
    for (const item of restarted.publishedModels()) {
      assert.equal(item.release.generatedAutomatically, true)
      assert.match(item.release.notes, /10 段标准调音/)
      assert.doesNotMatch(item.release.summary + item.release.notes + item.release.changelog, /样本|训练|误差|dB/)
    }
    const updated = new DatabaseSync(restarted.databasePath)
    assert.deepEqual(updated.prepare('SELECT model_id, published_at FROM audio_training_published_models ORDER BY model_id').all(), publications)
    assert.deepEqual(updated.prepare('SELECT * FROM audio_training_model_publication').get(), publication)
    assert.deepEqual(updated.prepare('SELECT * FROM audio_training_model_artifacts ORDER BY model_id').all(), artifacts)
    assert.deepEqual(updated.prepare('SELECT * FROM audio_training_models ORDER BY id').all(), models)
    const notes = updated.prepare('SELECT * FROM audio_training_published_models ORDER BY model_id').all()
    updated.close()
    restarted.close()
    restarted = createAudioTuningTrainingService({ directory: f.directory, logger: { error() {} } })
    const repeated = new DatabaseSync(restarted.databasePath)
    assert.deepEqual(repeated.prepare('SELECT * FROM audio_training_published_models ORDER BY model_id').all(), notes)
    repeated.close()
  } finally {
    restarted?.close()
    fs.rmSync(f.directory, { recursive: true, force: true })
  }
})


test('new publications automatically advance enabled distribution while preserving deliberate selection and disabled access', async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.now() })
  const f = fixture()
  try {
    await f.service.publishModel('first', 'fixture-full')
    t.mock.timers.tick(1000)
    const selected = await f.request('PUT', '/api/ai/config', configuration('first'), admin)
    const before = await f.request('GET', '/api/public/ai/config', null, user)
    t.mock.timers.tick(1000)
    await f.service.publishModel('second', 'fixture-full')
    const updated = await f.request('GET', '/api/public/ai/config', null, { ...user, 'if-none-match': before.headers.etag })
    assert.equal(updated.statusCode, 200)
    assert.equal(updated.body.resonance.model.id, 'second')
    assert.equal(updated.body.resonance.model.release.changelog, updated.body.resonance.model.release.notes)
    assert.equal(updated.body.revision, selected.body.revision)
    assert.equal(f.data.aiProviderConfig.resonance.model.id, 'first', 'reads do not mutate stored configuration')
    assert.equal((await f.request('GET', '/api/public/audio-training/models/second/coreml', null, user)).statusCode, 200)
    assert.equal((await f.request('GET', '/api/public/audio-training/models/first/coreml', null, user)).statusCode, 403)
    assert.equal((await f.request('GET', '/api/ai/config', null, admin)).body.resonance.model.id, 'second')
    t.mock.timers.tick(1000)
    await f.request('PUT', '/api/ai/config', configuration('first'), admin)
    assert.equal((await f.request('GET', '/api/public/ai/config', null, user)).body.resonance.model.id, 'first')
    const disabled = configuration('first')
    disabled.configuration = { wireProtocol: 'openAICompatible', baseURL: 'https://fixture.invalid/v1', model: 'fixture-model' }
    disabled.resonance.enabled = false
    await f.request('PUT', '/api/ai/config', disabled, admin)
    t.mock.timers.tick(1000)
    await f.service.publishModel('second', 'fixture-full')
    assert.equal((await f.request('GET', '/api/public/ai/config', null, user)).body.resonance.enabled, false)
    assert.equal((await f.request('GET', '/api/public/audio-training/models/second/coreml', null, user)).statusCode, 403)
  } finally { f.close() }
})
