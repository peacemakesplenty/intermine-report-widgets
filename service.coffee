#!/usr/bin/env coffee

flatiron  = require 'flatiron'
union     = require 'union'
connect   = require 'connect'
urlib     = require 'url'
fs        = require 'fs'
eco       = require 'eco'
cs        = require 'coffee-script'
uglifyJs  = require 'uglify-js'
cleancss  = require 'clean-css'
parserlib = require 'parserlib'

# Read the config file.
config = JSON.parse fs.readFileSync './config.json'
if not config.service? or
    not config.service.port? or
        typeof config.service.port isnt 'number'
            throw 'You need to specify the `port` to use by the server in the `service` portion of the config file'

app = flatiron.app
app.use flatiron.plugins.http,
    'before': [
        connect.static './public'
    ]
    'after':  []

app.start config.service.port, (err) ->
    throw err if err
    app.log.info "Listening on port #{app.server.address().port}".green if process.env.NODE_ENV isnt 'test'

# -------------------------------------------------------------------
# List all available widgets.
app.router.path "/widgets", ->
    @get ->
        app.log.info "Get a listing of available widgets"

        @res.writeHead 200, "content-type": "application/json"
        @res.write JSON.stringify config.widgets
        @res.end()

app.router.path "/widget", ->
    @get ->
        id = @req.query.id
        if id?
            app.log.info "Get widget " + id.bold

            # Is the callback provided?
            callback = @req.query.callback
            if callback?
                # Do we know this one?
                if config.widgets[id]?
                    # Load the presenter .coffee file.
                    path = "./widgets/#{id}/presenter.coffee"
                    try
                        isFine = fs.lstatSync path
                    catch e
                        @res.writeHead 500, "content-type": "application/json"
                        @res.write JSON.stringify 'message': "Widget `#{id}` is misconfigured, does not have a presenter defined"
                        @res.end()

                    if isFine?
                        # Bare-ly compile the presenter.
                        js = [
                            "(function() {\nvar root = this;\n\n  /**#@+ the presenter */"
                            ("  #{line}" for line in cs.compile(fs.readFileSync(path, "utf-8"), bare: "on").split("\n")).join("\n")
                        ]

                        # Tack on any config.
                        cfg = JSON.stringify(config.widgets[id].config) or '{}'
                        js.push "  /**#@+ the config */\n  var config = #{cfg};\n"

                        # Compile eco templates.
                        walk "./widgets/#{id}", /\.eco$/, (err, templates) =>
                            if err
                                @res.writeHead 500, "content-type": "application/json"
                                @res.write JSON.stringify 'message': "Widget `#{id}` is misconfigured, problem loading templates"
                                @res.end()
                            else
                                tml = [ "  /**#@+ the templates */\n  var templates = {};" ]
                                for file in templates
                                    template = eco.precompile fs.readFileSync file, "utf-8"
                                    name = file.split('/').pop()[0...-4]
                                    tml.push '  ' + minify "templates['#{name}'] = #{template}"
                                js.push tml.join "\n"

                                # Do we have a custom CSS file?
                                path = "./widgets/#{id}/style.css"
                                try
                                    exists = fs.lstatSync path
                                catch e
                                if exists
                                    # Read the file.
                                    css = fs.readFileSync path, "utf-8"
                                    # Prefix CSS selectors with a callback id.
                                    css = prefix css, "div#w#{callback}"
                                    # Escape all single quotes.
                                    css = css.replace /\'/g, "\\'"
                                    # Minify
                                    css = minify css, 'css'
                                    # Embed.
                                    exec = """
                                    \n/**#@+ css */
                                    var style = document.createElement('style');
                                    style.type = 'text/css';
                                    style.innerHTML = '#{css}';
                                    document.head.appendChild(style);\n
                                    """
                                    js.push ("  #{line}" for line in exec.split("\n")).join("\n")

                                # Finally add us to the browser `cache` under the callback id.
                                cb = """
                                /**#@+ callback from a cache */
                                (function() {
                                  var parent, part, _i, _len, _ref;
                                  parent = this;
                                  _ref = 'intermine.cache.widgets'.split('.');
                                  for (_i = 0, _len = _ref.length; _i < _len; _i++) {
                                    part = _ref[_i];
                                    parent = parent[part] = parent[part] || {};
                                  }
                                }).call(root);
                                """
                                js.push ("  #{line}" for line in cb.split("\n")).join("\n")
                                js.push "  root.intermine.cache.widgets['#{callback}'] = new Widget(config, templates);\n\n}).call(this);"

                                @res.writeHead 200, "content-type": "application/javascript;charset=utf-8"
                                @res.write js.join "\n"
                                @res.end()
                else
                    @res.writeHead 400, "content-type": "application/json"
                    @res.write JSON.stringify 'message': "Unknown widget `#{id}`"
                    @res.end()
            else
                @res.writeHead 400, "content-type": "application/json"
                @res.write JSON.stringify 'message': 'You need to specify a `callback` parameter'
                @res.end()
        else
            @res.writeHead 400, "content-type": "application/json"
            @res.write JSON.stringify 'message': 'You need to specify the widget in `id` parameter'
            @res.end()

# Traverse a directory and return a list of files (async, recursive).
walk = (path, filter, callback) ->
    results = []
    # Read directory.
    fs.readdir path, (err, list) ->
        # Problems?
        return callback err if err
        
        # Get listing length.
        pending = list.length
        
        return callback null, results unless pending # Done already?
        
        # Traverse.
        list.forEach (file) ->
            # Form path
            file = "#{path}/#{file}"
            fs.stat file, (err, stat) ->
                # Subdirectory.
                if stat and stat.isDirectory()
                    walk file, (err, res) ->
                        # Append result from sub.
                        results = results.concat(res)
                        callback null, results unless --pending # Done yet?
                # A file.
                else
                    if filter?
                        if file.match filter then results.push file
                    else
                        results.push file
                    callback null, results unless --pending # Done yet?

# Compress using `uglify-js` or `clean-css`.
minify = (input, type="js") ->
    switch type
        when 'js'
            jsp = uglifyJs.parser ; pro = uglifyJs.uglify
            pro.gen_code pro.ast_squeeze pro.ast_mangle jsp.parse input
        when 'css'
            cleancss.process input

# Prefix CSS selectors [prefix-css-node].
prefix = (input, text, blacklist=['html', 'body']) ->
    # Split on new lines.
    lines = input.split "\n"

    options =
        starHack: true
        ieFilters: true
        underscoreHack: true
        strict: false

    # Init parser.
    parser = new parserlib.css.Parser options

    index = 0
    shift = 0

    # Rule event.
    parser.addListener "startrule", (event) ->
        # Traverse all selectors.
        for selector in event.selectors
            # Where are we? Be 0 indexed.
            position = selector.col - 1

            # Make a char[] line.
            line = lines[selector.line - 1].split('')

            # Reset line shift if this is a new line.
            if selector.line isnt index then shift = 0

            # Find blacklisted selectors.
            blacklisted = false
            for part in selector.parts
                if part.elementName?.text in blacklist
                    blacklisted = true
                    el = part.elementName.text
                    p = part.col - 1 + shift

                    # Replace the selector with our own.
                    if p
                        # In the middle of the line?
                        line = line[0..p - 1].concat line[p..].join('').replace(new RegExp(el), text).split('')
                    else
                        line = line.join('').replace(new RegExp(el), text).split('')

            # Prefix with custom text.
            if not blacklisted
                line.splice(position + shift, 0, text + ' ')
                # Move the line shift.
                shift += text.length + 1
            
            # Join up.
            line = line.join('')

            # Check for `prefix` > `prefix` rules having replace 2 blacklisted rules.
            line = line.replace(new RegExp(text + " *\> *" + text), text)

            # Save the line back.
            lines[selector.line - 1] = line

            # Update the line.
            index = selector.line

    # Parse.
    parser.parse input

    # Return on joined lines.
    lines.join "\n"