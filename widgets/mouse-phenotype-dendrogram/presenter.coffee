# Simple assertion class.
class AssertException

    constructor: (@message) ->

    toString: -> "AssertException: #{@message}"

###
Set the assertion on the window object.
@param {boolean} exp Expression to be truthy
@param {string} message Exception text to show if `exp` is not truthy fruthy
###
@.assert = (exp, message) -> throw new AssertException(message) unless exp


# This class encapsulates the Widget behavior.
class Widget

    # PathQueries to fetch the allele terms for a symbol and high level terms for these terms.
    pq:
        alleleTerms:
            "select": [
                "Gene.symbol",
                "Gene.alleles.id",
                "Gene.alleles.genotypes.id",
                "Gene.alleles.genotypes.phenotypeTerms.id"
                "Gene.alleles.genotypes.phenotypeTerms.name"
            ],
            "constraints": []
        
        highLevelTerms:
            "select": [
                "Allele.highLevelPhenotypeTerms.name",
                "Allele.highLevelPhenotypeTerms.relations.childTerm.name"
            ],
            "constraints": []

    # Fetch phenotypic terms for PPARG mouse.
    alleleTerms: (cb) ->
        assert @config.symbol?, '`symbol` of the gene in question not provided'

        # Constrain on the symbol.
        pq = @pq.alleleTerms
        pq.constraints.push
            "path": "Gene"
            "op": "LOOKUP"
            "value": @config.symbol

        @service.query pq, (q) =>
            q.records (records) =>
                @max = 1 # top term count
                terms = {}
                # Terms to their counts.
                for allele in records[0]['alleles']
                    for genotype in allele.genotypes
                        for term in genotype.phenotypeTerms
                            if terms[term.name]?
                                terms[term.name].count += 1 # increase count
                                if terms[term.name].count > @max then @max = terms[term.name].count
                            else
                                terms[term.name] = 'count': 1 # new term
                
                # This will be one band.
                @band = @max / 4

                cb terms

    # Fetch high level terms for child terms.
    highLevelTerms: (children, cb) ->
        assert cb?, 'callback `cb` needs to be provided, we use async data loading'
        assert @config.symbol?, '`symbol` of the gene in question not provided'
        assert @band?, '`band` of allele counts not provided'

        # Constrain on these terms.
        pq = @pq.highLevelTerms
        pq.constraints.push
            "path": "Allele.highLevelPhenotypeTerms.relations.childTerm.name",
            "op": "ONE OF",
            "values": ( k for k, v of children )

        @service.query pq, (q) =>
            q.rows (rows) =>
                terms = {}

                # A map from high level terms to child terms (and eventually their counts).
                for [ parent, child ] in rows
                    if terms[parent]?
                        # add child terms and its count
                        terms[parent].children.push
                            'name': child
                            'count': children[child].count
                            'band': Math.floor(children[child].count / @band)
                            'depth': 2 # leaf node (branch node more like)
                    else
                        terms[parent] =
                            'name': parent
                            'children': [] # new term
                            'depth': 1 # high level term depth

                # Arrayize on non empty HLTs.
                @hlts = []
                terms = ( ( do => @hlts.push(t.name) ; t ) for t in _(terms).toArray() when t.children.length isnt 0 )

                cb 'name': @config.symbol, 'children': terms, 'depth': 0

    # Create a new service connection.
    constructor: (@config, @templates) ->
        @service = new intermine.Service 'root': 'http://metabolicmine.org/beta/service/'

    # Render the graph.
    render: (@target) ->
        # Render the widget wrapper.
        $(@target).html @templates.widget
            'title': "Alleles phenotype terms for #{@config.symbol}"

        # Fetch phenotypic terms for PPARG mouse.
        @alleleTerms (children) =>
            # Fetch high level terms for child terms.
            @highLevelTerms children, @renderGraph

    ###
    Once data are loaded or updated, render the dendrogram and init config for it.
    @param {object} data A root to children object to render.
    ###
    renderGraph: (data) =>
        assert typeof data is 'object' and data.children?, '`data` needs to be an Object with `children`'
        assert @target?, 'need to have a target for rendering defined'
        assert Tangle?, 'Tangle lib does not seem to be loaded'
        assert @band?, '`band` of allele counts not provided'
        assert @max?, '`max` top allele count not provided'
        assert @hlts? and @hlts instanceof Array, '`hlts` needs to be populated by an Array of High Level Terms'
        
        # Show the config for the graph.
        $(@target).find('.config').html @templates.config()

        # Populate the list of HLTs in the config.
        l = $(@target).find('.config .terms ul')
        # Append the actual `li`.
        ( l.append $('<li/>', 'class': 'option', 'text': term ) for term in @hlts )
        
        # Now that we have them all add events to them.
        $(@target).find('.config .terms .option').click (e) =>
            assert tangle?, 'wow a bit too fast there fella'
            
            # Remove all other.
            $(@target).find('.config .terms .option.selected').removeClass('selected')
            # Select us.
            $(e.target).addClass('selected')
            # Update the graph (setting a value triggers and update() event).
            tangle.setValue 'showCategory', $(e.target).text()

        # Switch between graph types.
        $(@target).find('.config .types .option').click (e) =>
            assert tangle?, 'wow a bit too fast there fella'
            
            # Remove all other.
            $(@target).find('.config .types .option.selected').removeClass('selected')
            # Select us.
            $(e.target).addClass('selected')
            # Update the graph (setting a value triggers and update() event).
            tangle.setValue 'type', $(e.target).text()

        # Reactivize document.
        widget = @
        tangle = new Tangle $(@target).find('.config')[0],
            initialize: ->
                # Show term text when...
                @termTextBand = 3
                # Hide terms when...
                @hideTermsBand = 2
                # Only show terms in HLT...
                @showCategory = 'all'
                # Which type?
                @type = 'radial'

            update: ->
                # Show term text when...
                @termTextCount = (@termTextBand - 1) * widget.band
                # Hide terms when...
                @hideTermsCount = (@hideTermsBand - 1) * widget.band
                
                # Re-render the graph.
                widget.dendrogram data, @

    # Render the dendrogram node graph.
    dendrogram: (data, opts) =>
        assert @target?, 'need to have a target for rendering defined'
        assert @config.width?, 'need to provide a `width` for the chart'
        assert @config.height?, 'need to provide a `height` for the chart'
        assert typeof opts is 'object', '`opts` of the graph are not provided by Tangle, go untangle'

        # Filter nodes with a low band.
        # ...also make a deep copy of `data`.
        # ...also prune level 1 nodes that are empty.
        # ...also filter on HLT category.
        data = (filterChildren = (node, bandCutoff, category) ->
            assert node?, '`node` not provided'
            assert bandCutoff?, '`bandCutoff` not provided'
            assert category?, '`category` not provided'

            # A HLT?
            if node.depth is 1
                # Do not show HLTs that have no children.
                return if !node.children? or node.children.length is 0
                # Do not show HLTs if we have constrained on category.
                return if category isnt 'all' and node.name isnt category
            # Do not process further if we do not have children.
            return node unless node.children? and node.children.length > 0

            assert node.children?, 'need children at this point, knock me up!'

            # Prep for deep copy.
            children = []
            
            # Traverse the original.
            for ch in node.children
                # Do we have chomping to do?
                unless ch.band? and ch.band < (bandCutoff - 1)
                    # Children of our own?
                    ch = filterChildren ch, bandCutoff, category
                    # Push to new arr?
                    children.push ch if ch?

            # Replace orig.
            unless children.length is 0
                'name':     node.name  # string
                'count':    node.count # number
                'band':     node.band  # number
                'children': children   # deep copy array
        
        ) data, opts.hideTermsBand, opts.showCategory

        # Target.
        target = $(@target).find('.graph')

        # Clear any previous content.
        target.empty()

        # Do we actually have anything to show?
        unless data?
            # Show a message of this fact instead.
            return target.html $ '<div/>', 'class': 'alert-box', 'text': 'Nothing to show. Adjust the filters above to display the graph.'

        params =
            'termTextBand': opts.termTextBand
            'data':         data
            'width':        @config.width
            'height':       @config.height
            'el':           target[0]

        switch opts.type
            when 'radial' then new RadialDendrogram params
            when 'tree'   then new TreeDendrogram   params


# Represents a Dendrogram Node graph in a radial/circular fashion.
class RadialDendrogram

    constructor: (opts) ->
        assert opts.width? and typeof opts.width is 'number', '`width` is missing and needs to be a number'
        assert opts.height? and typeof opts.height is 'number', '`height` is missing and needs to be a number'
        assert opts.el? and typeof opts.el is 'object', '`el` is missing and needs to be an HTMLDivElement'
        assert typeof opts.data is 'object', '`data` need to be provided in an Object form, read up on D3.js'
        assert opts.termTextBand?, "`termTextBand` representing the node text cutoff not present"

        ( @[key] = value for key, value of opts )

        rx = @width / 2
        ry = @height / 2
        
        # Sorting function for sibling nodes.
        sort = (a, b) ->
            switch a.depth - b.depth
                # Based on depth.
                when -1 then return -1
                when 1 then return 1
                else
                    # Based on count.
                    return a.count - b.count if a.count? and b.count?
            0

        # Create a dendrogram layout going all the way round with the width of ry - 50.
        cluster = d3.layout.cluster().size([360, ry - 50]).sort(sort)
        
        # Diagonal generator producing smooth fan.
        diagonal = d3.svg.diagonal.radial().projection (d) -> [d.y, d.x / 180 * Math.PI]
        
        # Wrapper SVG.
        vis = d3.select(@el).append("svg:svg")
            .attr("width", @width)
            .attr("height", @height)
            # Center the graph.
            .append("svg:g")
                .attr("transform", "translate(#{rx},#{ry})")

        # Draw the white arc where the end nodes lie.
        arc = vis.append("svg:path")
            .attr("class", "arc")
                .attr("d", d3.svg.arc().innerRadius(ry - 50).outerRadius(ry - 20).startAngle(0).endAngle(2 * Math.PI))

        # Create cluster nodes from data.
        nodes = cluster.nodes(@data)

        # Create links between the nodes.
        links = vis.append("svg:g")
            .attr("class", "links")
        for link in cluster.links(nodes)
            links.append("svg:path")
                .attr("class", if link.target.band? then "link band-#{link.target.band}" else 'link')
                .attr("d", diagonal(link))
        
        # Create three depths to draw from the back forward.
        n = vis.append("svg:g").attr("class", "nodes")
        depths = [
            n.append("svg:g").attr("class", "tier depth-2")
            n.append("svg:g").attr("class", "tier depth-1")
            n.append("svg:g").attr("class", "tier depth-0")
        ]

        # Create the actual nodes.
        for d in nodes
            node = depths[Math.abs(d.depth - 2)].append("svg:g")
                .attr("class", if d.count? then "node depth-#{d.depth} count-#{d.count}" else "node depth-#{d.depth}")
                .attr("transform", "rotate(#{d.x - 90})translate(#{d.y})")

            # Draw a node circle.
            node.append("svg:circle")
                .attr("r", Math.abs(d.depth - 6))
                .attr("class", "band-#{d.band}" if d.band )

            # Append a rotated text to the node.
            node.append("svg:title")
                .text(d.name)

            # Show text only for the top 'band' terms.
            if !d.band? or d.band > (@termTextBand - 2)
                node.append("svg:text")
                    .attr("dx", if d.x < 180 then 8 else -8)
                    .attr("dy", ".31em")
                    .attr("text-anchor", if d.x < 180 then "start" else "end")
                    .attr("transform", if d.x < 180 then null else "rotate(180)")
                    .text(if d.name.length > 50 then d.name[0...50] + '...' else d.name)


# Represents a Dendrogram Node graph in a square/tree fashion.
class TreeDendrogram

    constructor: (opts) ->
        assert opts.width? and typeof opts.width is 'number', '`width` is missing and needs to be a number'
        assert opts.height? and typeof opts.height is 'number', '`height` is missing and needs to be a number'
        assert opts.el? and typeof opts.el is 'object', '`el` is missing and needs to be an HTMLDivElement'
        assert typeof opts.data is 'object', '`data` need to be provided in an Object form, read up on D3.js'
        assert opts.termTextBand?, "`termTextBand` representing the node text cutoff not present"

        ( @[key] = value for key, value of opts )

        # Sorting function for sibling nodes.
        sort = (a, b) ->
            switch b.depth - a.depth
                # Based on depth.
                when -1 then return -1
                when 1 then return 1
                else
                    # Based on count.
                    return b.count - a.count if a.count? and b.count?
            0

        # Create a dendrogram layout.
        cluster = d3.layout.cluster().size([@height, @width / 2]).sort(sort)
        
        # Diagonal generator producing smooth fan.
        diagonal = d3.svg.diagonal().projection( (d) -> [d.y, d.x] )
        
        # Wrapper SVG.
        vis = d3.select(@el).append("svg")
            .attr("width", @width)
            .attr("height", @height)
                .append("g")
                    .attr("transform", "translate(120, 0)")
        
        # Create cluster nodes from data.
        nodes = cluster.nodes(@data)
        
        # Create links between the nodes.
        links = vis.append("svg:g")
            .attr("class", "links")
        for link in cluster.links(nodes)
            links.append("svg:path")
                .attr("class", if link.target.band? then "link band-#{link.target.band}" else 'link')
                .attr("d", diagonal(link))
        
        # Create three depths to draw from the back forward.
        n = vis.append("svg:g").attr("class", "nodes")
        depths = [
            n.append("svg:g").attr("class", "tier depth-2")
            n.append("svg:g").attr("class", "tier depth-1")
            n.append("svg:g").attr("class", "tier depth-0")
        ]

        # Create the actual nodes.
        for d in nodes
            node = depths[Math.abs(d.depth - 2)].append("svg:g")
                .attr("class", if d.count? then "node depth-#{d.depth} count-#{d.count}" else "node depth-#{d.depth}")
                .attr("transform", "translate(#{d.y},#{d.x})")

            # Draw a node circle.
            node.append("svg:circle")
                .attr("r", Math.abs(d.depth - 6))
                .attr("class", "band-#{d.band}" if d.band )

            # Append a rotated text to the node.
            node.append("svg:title")
                .text(d.name)

            # Show text only for the top 'band' terms.
            if !d.band? or d.band > (@termTextBand - 2)
                node.append("svg:text")
                    .attr("dx", if d.children then -8 else 8)
                    .attr("dy", "3")
                    .attr("text-anchor", if d.children then "end" else "start")
                    .text(if d.name.length > 50 then d.name[0...50] + '...' else d.name)