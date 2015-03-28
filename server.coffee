exec = require('child_process').exec
path = require 'path'

Hapi = require 'hapi'
_ = require 'lodash'
Wreck = require 'wreck'
redis = require 'redis'
redClient = redis.createClient()

SECOND = 1000
MINUTE = 60 * SECOND
HOUR = 60 * MINUTE

{SITE_ID, DATA_URL} = global

server = new Hapi.Server {
  cache: require('catbox-redis')
}

server.connection {
  port: 8088
  routes:
    cors:
      additionalHeaders: ['X-Requested-With']
      override: false
}

server.register {
    register: require 'good'
    options:
      reporters: [
        {
          reporter: require('good-console')
          args: [{log: '*', response: '*'}]
        }
      ]
  }, (err) ->
    if err
      console.log 'Failed loading good plugin',
      console.error err
    else
      console.log 'Good lugin is good.'

getData = (next) ->
  Wreck.get DATA_URL, {json: true}, (err, resp, payload) ->
    console.log 'serverData is fresh.'
    next err, payload

server.method 'serverData', getData,
  cache:
    expiresIn: 48*HOUR
    staleIn: MINUTE
    staleTimeout: 10

server.route
  method: "GET"
  path: "/index.json"
  handler: (request, reply) ->
    # May return stale data.
    server.methods.serverData (err, res) ->
      if err then console.error err
      return reply err or res

server.route
  method: 'GET'
  path: '/{path*}'
  handler: (req, reply) ->
    p = req.url.path
    if path.extname(p)
      return reply.file("public/#{p}")

    redClient.hget 'rjsRoute.h.'+SITE_ID, p, (err, res) ->
      if err then return reply err
      if res then return reply res
      console.log SITE_ID, p, 'not in redis'
      scriptPath = path.resolve(__dirname, 'renderMarkup.coffee')
      exec "coffee #{scriptPath} --path='#{p}' --host=#{SITE_ID}", (err, stdout, stderr) ->
        if err or stderr
          console.error err
          return reply err or stderr
        else
          unless stdout is "ok\n"
            try
              info = JSON.parse(stdout)
              if info?.to
                return reply.redirect info.to
            catch
              console.log stdout
          redClient.hget 'rjsRoute.h.'+SITE_ID, p, (err, res) ->
            if err then return reply err
            return reply res

server.start ->
  console.log "info", "Server running at: " + server.info.uri
  return
