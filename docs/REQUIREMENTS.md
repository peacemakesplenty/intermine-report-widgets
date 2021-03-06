## Requirements

### Service

1. Compile *templates* into their JS form and make them accessible within the context of the widget only.
2. Make *CSS* available only in the context of the widget, perhaps by prefixing each declaration with a dynamic *widget id* using [prefix-css-node](https://github.com/radekstepan/prefix-css-node) or [css-prefix](https://github.com/substack/css-prefix).
3. Respond to the client with a list of *resources* that need to be loaded beforing rendering the widget.
4. Each widget consists of:
  1. One [CoffeeScript](http://coffeescript.org/) *presenter* containing the logic getting data from the *model* using [imjs](https://github.com/alexkalderimis/imjs).
  2. A number of [eco](https://github.com/sstephenson/eco/) *templates* precompiled.
  3. One *CSS* file specifically for the widget.
  4. Any extra *config* dynamically populated for the widget to consume. This could be the mine the Widget is to take data from or extra flags that specialize an otherwise generic Widget.
  5. Optional number of requirements (CSS, JS), loaded from the [CDN](https://github.com/intermine/CDN).
5. All of the previous are configured by the user and the service validates that all widgets are executable.
6. *Data* requests are done from within the widget to speed up their initial loading.
7. Files are served as UTF-8.
8. Provide nice URL for fetching the widgets so it is easier to debug them in Network view, `/widget/24517/publications-displayer`.
9. Provide info messages on each step of the compilation process so we can determine where problems lie. These then be returned as `message` to the user when requesting widgets as HTTP 500 JSON errors.

#### Optional

* Cache resources by, for example, not packaging resources on the fly but doing so on service startup. Then, say the latest modification date. Add `ETag` and return 304 not modified then.
* Allow the use of [LESS](http://lesscss.org/) instead of CSS.
* Allow the use of other templating languages.
* Check for the presence of `Displayer.prototype.render` and `Displayer.prototype.initialize` in the compiled *presenter*.
* Validate that callbacks are valid JavaScript identifiers. Should not be needed as we will use API loader and generate these automagically.
* Provide a signature in the generated output describing the title, author etc for the widget in question.
* Each block in the compiled result have a comment header so it is easier to find where things lie when debugging.
* Provide connection to [imjs](https://github.com/alexkalderimis/imjs) by default.

#### Issues

* If we want to split presenter across multiple CoffeScript files, how to maintain their order in the resulting JS version? Go alphabetically?

### Client

1. Make use of [intermine-api-loader](https://github.com/radekstepan/intermine-api-loader) to efficiently load resources and libs only when needed.
2. Generate *callbacks* that are unique for the page taking into account other clients that could exist on the page. As the service URL is unique per client, make use of that.
3. Dump error messages from the server into the target element where widget was supposed to have been.
4. Cache all of the widgets listing as we need to be resolving widget dependencies first.
5. Provide a wrapping `article` element with a predictable `im-report-widget` class so we can use it in our CSS.

#### Optional

* Provide a callback where all widgets can dump error messages.

## Creating a new Report Widget

First config needs to be provided.

* Entries in the `dependencies` list are resolved before the widget package itself is fetched.
* Any properties in the `config` object are passed into the widget.

```json
{
    "publications-displayer": {
        "author": "Radek",
        "title": "Publications for Gene",
        "description": "Shows a list of publications for a specific gene",
        "version": "0.1.1",
        "dependencies": [
            {
                "name": "jQuery",
                "path": "http://127.0.0.1:1119/js/jquery-min.js",
                "type": "js",
                "wait": true
            },
            {
                "name": "_",
                "path": "http://127.0.0.1:1119/js/underscore-min.js",
                "type": "js",
                "wait": true
            },
            {
                "name": "Backbone",
                "path": "http://127.0.0.1:1119/js/backbone-min.js",
                "type": "js"
            },
            {
                "path": "http://127.0.0.1:1119/js/imjs.js",
                "type": "js"
            }
        ],
        "config": {
            "mine": "http://beta.flymine.org/beta",
            "pathQuery": {
                "select": [
                    "publications.title",
                    "publications.year",
                    "publications.journal",
                    "publications.pubMedId",
                    "publications.authors.name"
                ],
                "from": "Gene",
                "joins": [
                    "publications.authors"
                ]
            }
        }
    }
}
```

The next step is writing a *presenter* which is a component that knows how to get data for itself and then render them in a particular way, thus it encapsulates the behavior of the widget.

The file needs to be called `presenter.coffee` and be placed in a directory with the name of the widget, in our case `/widgets/publications-displayer/`. The file needs to contain a class `Widget` with the following signature:

```coffee-script
class Widget

    # Have access to config and templates compiled in.
    constructor: (config, templates) ->

    # Render accepts a target to draw results into.
    render: (target) ->
```

In JavaScript terms this corresponds to:

```javascript
var Widget;

Widget = (function() {

    function Widget(config, templates) {}

    Widget.prototype.render = function(target) {};

    return Widget;

})();
```

Other files are optional. For example, one can have as many templates as they want, all saved with `.eco` suffix and these will be available as functions in the above mentioned `templates` object passed to the constructor of the widget.

Also, a CSS file called `style.css` can be present in which case each selector will be prefixed with a unique id of the widget so the style is only applied to the widget itself and not other elements on the page.