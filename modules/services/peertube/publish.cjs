const { readFile } = require('node:fs/promises')

const hooks = [
  'filter:api.video.upload.accept.result',
  'filter:api.video.update-file.accept.result',
  'filter:api.live-video.create.accept.result',
  'filter:api.video.pre-import-url.accept.result',
  'filter:api.video.pre-import-torrent.accept.result',
  'filter:api.video.post-import-url.accept.result',
  'filter:api.video.post-import-torrent.accept.result',
  'filter:api.video.user-import.accept.result'
]

async function mayPublish (user) {
  if (user?.role === 0 && !user.pluginAuth) return true
  if (user?.pluginAuth !== 'peertube-plugin-auth-openid-connect' || !user.pluginAuthExternalId) return false

  try {
    const { expires, subjects } = JSON.parse(await readFile('/run/peertube-access/publish.json', 'utf8'))
    return Date.now() < expires && subjects.includes(user.pluginAuthExternalId)
  } catch {
    return false
  }
}

async function register ({ registerHook }) {
  for (const target of hooks) {
    registerHook({
      target,
      handler: async (result, { user }) => {
        if (!result?.accepted || await mayPublish(user)) return result
        return { accepted: false, errorMessage: 'Publishing requires membership in PeerTube Publishers.' }
      }
    })
  }
}

async function unregister () {}

module.exports = { register, unregister }
