#!/usr/bin/env coffee
flatiron = require 'flatiron'
union    = require 'union'
connect  = require 'connect'
urlib    = require 'url'
winston  = require 'winston'
growl    = require 'growl'
fs       = require 'fs'

# A Winston and Growl logger?
log = {}
logger = new winston.Logger()
logger.add(winston.transports.Console, {level: 'debug'})
logger.cli()
for lvl in [ 'info', 'warn', 'debug', 'data', 'error' ] then do (lvl) ->
    log[lvl] = (text) ->
        # Show using Winston.
        logger[lvl](text)

        # Strip colors and show in Growl.
        if lvl in [ 'info', 'warn', 'error' ]
            try
                growl text.replace(/\033\[[0-9;]*m/g, ''), 'title': 'InterMine Report Widgets'
            catch err
                # Silence!

# Require builder with out logger.
build = require('./build.coffee') log

# Read the config file.
config = do ->
    cache = null

    # Invalidate the cache on config update.
    fs.watch './config.json', ->
        log.warn 'Config file got updated'
        cache = null

    # Return this config getter.
    (cb) ->
        return cb null, cache if cache

        # Read & parse the file.
        fs.readFile './config.json', 'utf-8', (err, data) ->
            return cb err if err
            
            try
                data = JSON.parse data
            catch err
                log.error "config.json is invalid"
                return cb err

            # Validate that the config has widgets that are accessible by us.
            for id in Object.keys data.widgets
                if encodeURIComponent(id) isnt id
                    return cb "Widget id `#{id}` is not a valid name and cannot be used, use encodeURIComponent() to check"

            # Cache & return.
            cb null, cache = data

# Init the app.
app = flatiron.app
app.use flatiron.plugins.http,
    'before': [
        connect.static './public'
    ]
    'after':  []

# -------------------------------------------------------------------
# List all available widgets.
app.router.path "/widget/report", ->
    @get ->
        log.debug "Get a listing of available widgets"

        # Do we have a callback?
        callback = @req.query?.callback
        if callback?
            # Only provide deps for each widget much like InterMine.
            config (err, data) =>
                if err
                    log.error "Request failed: #{ err }"
                    console.log err.stack
                    @res.writeHead 500, "content-type": "application/json"
                    @res.write JSON.stringify 'message': err
                    @res.end()
                else
                    out = {}
                    for widget, stuff of data.widgets
                        out[widget] = stuff.dependencies

                    @res.writeHead 200, "content-type": "application/javascript;charset=utf-8"
                    @res.write "#{callback}(#{JSON.stringify(out)});"
                    @res.end()
        else
            @res.writeHead 500, "content-type": "application/json"
            @res.write JSON.stringify 'message': 'Provide a `callback` parameter so we can respond with JSONP'
            @res.end()

app.router.path "/widget/report/:widgetId", ->
    @get (widgetId) ->
        log.debug "Get widget " + widgetId.bold

        # Do we have a callback?
        callback = @req.query?.callback
        if callback?
            config (err, data) =>
                if err
                    @res.writeHead 500, "content-type": "application/json"
                    @res.write JSON.stringify 'message': err
                    @res.end()
                else
                    # Do we know this one?
                    widget = data.widgets[widgetId]
                    if widget?
                        # Run the precompile.
                        build.single widgetId, callback, widget, (err, js) =>
                            if err
                                # Catch all errors into logs and JSON messages.
                                log.error err.red

                                @res.writeHead 500, 'content-type': 'application/json'
                                @res.write JSON.stringify 'message': err
                                @res.end()
                            else
                                # Write the output.
                                @res.writeHead 200, "content-type": "application/javascript;charset=utf-8"
                                @res.write js
                                @res.end()
                    else
                        @res.writeHead 400, "content-type": "application/json"
                        @res.write JSON.stringify 'message': "Unknown widget `#{widgetId}`"
                        @res.end()
        else
            @res.writeHead 400, "content-type": "application/json"
            @res.write JSON.stringify 'message': 'Callback not provided'
            @res.end()

# Check we can read the config, and then start the app.
config (err) ->
  if err?
    log.error "Cannot start app: config is invalid: #{ err }"
    process.exit 1
  else
    app.start process.env.PORT, (err) ->
        throw err if err
        log.info "Listening on port #{String(app.server.address().port).bold}".green
