nodejsx = require 'coffee-react/register'
React = require 'react'
redis = require 'redis'
Wreck = require 'wreck'

argv = require('minimist')(process.argv.slice(2))

unless argv.host # host to do redis look.
  return console.error 'host is required.'
unless argv.path
  return console.error 'path is required.'

redClient = redis.createClient()

siteId = argv.host

App = require '../../app/app'

REDKEYh = 'rjsRoute.h.'+siteId
REDKEYz = 'rjsRoute.z.'+siteId

render = (Handler, props) ->
  markup = React.renderToString React.createElement(Handler, props)
  markup = "<!doctype html>\n" + markup
  redClient.hset REDKEYh, argv.path, markup, (err, res) ->
    if err
      redClient.quit()
      throw err
  redClient.zincrby REDKEYz, 1, argv.path, (err, res) ->
    redClient.quit()
    throw err if err
  console.log 'ok'

onError = (err) ->
  console.error err
  redClient.quit()

onAbort = (abortReason) ->
  console.log JSON.stringify(abortReason)
  redClient.quit()

handleDataRes = (data) ->
  data.path = argv.path
  data._dataId = siteId
  # Trigger render.
  App data, render, onError, onAbort

# data = encodeURIComponent(encodeURIComponent(config))
redCacheId = "hapi-cache:%23serverData:"+siteId

redClient.get redCacheId, (err, res) ->
  if err
    redClient.quit()
    throw err
  if res
    handleDataRes(JSON.parse(res).item)
  else
    url = "http://localhost:8088/index.json"
    # console.log 'No data found in Redis.', url
    # No data in Redis so we need to make http request to get it.
    Wreck.get url, {json: true}, (err, resp, payload) ->
      if err
        redClient.quit()
        throw err
      handleDataRes(payload)

  return
