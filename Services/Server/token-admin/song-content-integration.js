const fs = require('node:fs')
const path = require('node:path')
const songContentRoot = fs.existsSync(path.join(__dirname, 'song-content'))
  ? './song-content'
  : '../song-content'
const {
  createSongContentService,
  installSongContentRoutes
} = require(`${songContentRoot}/song-content-service`)
const { installSongContentAdminRoutes } = require(`${songContentRoot}/song-content-admin`)
const { installSongContentOperationsRoutes } = require(`${songContentRoot}/song-content-operations`)
const {
  createConfiguredContentGenerator,
  createSongContentConfigStore,
  installSongContentConfigRoutes
} = require(`${songContentRoot}/song-content-config`)
const { createAnnouncementService, installAnnouncementRoutes } = require('./announcement-service')
const {
  createAudioTuningTrainingService,
  installAudioTuningTrainingRoutes
} = require(`${songContentRoot}/audio-tuning-training`)
const {
  createTrainingSampleStore,
  installTrainingSampleRoutes
} = require(`${songContentRoot}/audio-training-samples`)

/**
 * Mounts the song-content API on the existing token Express application.
 * Platform lookup, evidence collection and model invocation stay injectable so
 * the token service can reuse its existing provider clients and credentials.
 */
function installTokenSongContent({
  app,
  dataDirectory,
  resolvePublicToken,
  publicRateLimit,
  authMiddleware,
  authorize,
  bootstrapAdminActorId = 'token-admin',
  adminUIRoot,
  platformResolver,
  sourceCollector,
  contentGenerator,
  appAIConfigProvider,
  schemaVersion = '3',
  promptVersion = 'song-editor-web-v7',
  autoPublish = true,
  startWorker = true,
  encryptionKey = process.env.SONG_CONTENT_MASTER_KEY,
  logger = console
}) {
  if (!dataDirectory) throw new TypeError('token server dataDirectory is required')

  let configStore = null
  const resolvedContentGenerator = typeof contentGenerator === 'function'
    ? contentGenerator
    : async (context) => {
        if (!configStore) throw new Error('song-content configuration is not ready')
        return createConfiguredContentGenerator({ configStore, appAIConfigProvider })(context)
      }

  const effectivePolicyProvider = async () => {
    const contentPolicy = configStore ? configStore.current().ai : {}
    const appAI = typeof appAIConfigProvider === 'function'
      ? (await appAIConfigProvider() || {})
      : {}
    return {
      ...contentPolicy,
      providerUsageLimits: serverProviderUsageLimits(appAI.usageLimits)
    }
  }

  const service = createSongContentService({
    directory: path.join(dataDirectory, 'song-content'),
    platformResolver,
    sourceCollector,
    contentGenerator: resolvedContentGenerator,
    schemaVersion,
    promptVersion,
    autoPublish: () => configStore ? configStore.current().ai?.autoPublish === true : autoPublish,
    policyProvider: effectivePolicyProvider,
    startWorker,
    logger
  })

  if (typeof authorize !== 'function') {
    service.store.assignRole(bootstrapAdminActorId, 'content-admin', 'system-bootstrap')
  }
  const resolvedAuthorize = typeof authorize === 'function'
    ? authorize
    : (permission) => (req, res, next) => {
        const actorId = String(req.admin?.id || req.user?.id || req.auth?.id || bootstrapAdminActorId)
        if (!service.store.actorPermissions(actorId).includes(permission)) {
          return res.status(403).json({ error: '权限不足', code: 'FORBIDDEN' })
        }
        next()
      }

  const publicAccessMiddleware = typeof resolvePublicToken === 'function'
    ? (req, res, next) => {
        const credential = resolvePublicToken(req, res)
        if (!credential) return
        req.songContentCredential = credential
        next()
      }
    : null

  installSongContentRoutes({
    app,
    service,
    publicAccessMiddleware,
    publicRateLimit,
    logger
  })

  configStore = createSongContentConfigStore({
    databasePath: service.store.databasePath,
    encryptionKey,
    logger
  })
  installSongContentConfigRoutes({
    app,
    configStore,
    authMiddleware,
    authorize: resolvedAuthorize,
    publicAccessMiddleware,
    publicRateLimit,
    appAIConfigProvider,
    audit: (entry) => service.store.appendAudit(entry),
    logger
  })

  if (typeof authMiddleware === 'function') {
    installSongContentAdminRoutes({ app, service, authMiddleware, authorize: resolvedAuthorize, logger })
    installSongContentOperationsRoutes({ app, service, authMiddleware, authorize: resolvedAuthorize })
  }

  const announcementService = createAnnouncementService({ databasePath: service.store.databasePath, logger })
  installAnnouncementRoutes({
    app,
    service: announcementService,
    authMiddleware,
    authorize: resolvedAuthorize,
    resolvePublicToken,
    audit: (entry) => service.store.appendAudit(entry),
    logger
  })

  // Complete tuning samples arrive through their own bounded intake instead of
  // riding inside the full playlist snapshot.
  const trainingSampleStore = createTrainingSampleStore({ directory: dataDirectory, logger })
  installTrainingSampleRoutes({
    app,
    store: trainingSampleStore,
    publicAccessMiddleware,
    publicRateLimit,
    logger
  })

  const audioTrainingService = createAudioTuningTrainingService({
    directory: path.join(dataDirectory, 'audio-training'),
    cloudDatabasePath: path.join(dataDirectory, 'cloud-storage.sqlite'),
    trainingSampleDatabasePath: trainingSampleStore.databasePath,
    coreMLPythonPath: process.env.AUDIO_TRAINING_PYTHON
      || path.join(dataDirectory, 'audio-training-runtime', 'bin', 'python'),
    logger
  })
  app.locals ||= {}
  app.locals.audioTrainingDistribution = {
    service: audioTrainingService,
    authorize: resolvedAuthorize('training.manage')
  }
  installAudioTuningTrainingRoutes({
    app,
    service: audioTrainingService,
    authMiddleware,
    authorize: resolvedAuthorize,
    resolvePublicToken,
    audit: (entry) => service.store.appendAudit(entry),
    logger
  })

  if (adminUIRoot) {
    app.get(['/agents', '/agent-management'], (_req, res) => {
      res.sendFile(path.resolve(adminUIRoot, 'song-content.html'))
    })
    app.get('/announcements', (_req, res) => {
      res.sendFile(path.resolve(adminUIRoot, 'announcements.html'))
    })
  }

  const closeService = service.close.bind(service)
  service.configStore = configStore
  service.announcementService = announcementService
  service.audioTrainingService = audioTrainingService
  service.trainingSampleStore = trainingSampleStore
  service.close = () => {
    audioTrainingService.close()
    trainingSampleStore.close()
    announcementService.close()
    configStore.close()
    closeService()
  }

  return service
}

function serverProviderUsageLimits(clientUsageLimits = {}) {
  return {
    minimumRequestInterval: Math.max(0, Number(clientUsageLimits.minimumRequestInterval) || 0),
    hourlyRequestLimit: 0,
    dailyRequestLimit: 0
  }
}

module.exports = { installTokenSongContent, serverProviderUsageLimits }
