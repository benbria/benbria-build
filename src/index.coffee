ninjaFactories  = require './ninjaFactories'
{findScript}    = require './ninjaCommands'
_               = require 'lodash'
log             = require('yadsil')('index')
glob            = require 'glob'

# Collect all the coffee files across the project.
#
# This is used for linting purposes.
#
collectCoffeeFiles = ({extensions, paths}) ->
    log.info 'looking for coffee script files..'
    extensionMark = '$ext'
    _.chain(paths)
    .map((path) ->
        extensions.map (ext) -> path.replace extensionMark, ext
    )
    .flatten()
    .map((path) ->
        glob.sync path
    )
    .flatten()
    .value()

# Default lint options to use on projects with the assumed directory
# structure. They can be overridden via the `configureCoffeelint` below
#
defaultLintOptions = {
    extensions: [
        'coffee'
        '_coffee'
    ]
    paths: [
        'src/**/*.$ext'
        'assets/js/**/*.$ext'
        'bin/**/*.$ext'
        'Gruntfile.$ext'
    ]
}

setLintOptions = null

# Expose the option to override default coffeelint paths.
#
exports.configureCoffeelint = (options) ->
    setLintOptions = options

# Collect all the coffee files to lint based on the currently set options
#
exports.getCoffeelintPaths = ->
    collectCoffeeFiles setLintOptions ? defaultLintOptions

# Register a factory.  See ninjaFactories.coffee for details.
exports.defineFactory = ninjaFactories.defineFactory

#
# * `sourceFile` is the entry file for browserify.
#   (e.g. "browserify/foo/foo.coffee")
# * `targetFile` is the js file to write, relative to `build/assets/{release|debug}/js`.  This will
#   automatically generate an i18n file and deps file. (e.g. "foo/foo.js")
# * `options.extensions` is a list of extensions to automatically require (e.g. ['.coffee'].)
# * `options.transforms` is a list of transform names to use (e.g. ['coffeeify'].)
#
exports.defineBrowserifyFactory = (name, sourceFile, targetFile, options) ->
    exports.defineFactory "browserify-#{name}", {
        makeRules: (ninja, config) ->
            ['debug', 'release'].forEach (releaseType) ->
                cli = "$node #{findScript 'browserify-bundle.js'}"
                if options.extensions then cli += " --extensions '#{options.extensions.join ","}'"
                if options.transforms then cli += " --transforms '#{options.transforms.join ","}'"
                cli += " --out $out --i18n $out.i18n"
                if releaseType is 'debug'
                    cli += " --deps $out.d --debug"
                cli += " ./$in"

                rule = ninja.rule("browserify-#{name}-#{releaseType}")
                rule.run(cli)
                if releaseType is 'debug' then rule.depfile('$out.d')
                rule.description "(#{releaseType}) BROWSERIFY $in"

        assetFiles: sourceFile

        makeAssetEdge:  (ninja, source, target, releaseType) ->
            target = "build/assets/#{releaseType}/js/#{targetFile}"
            ninja.edge(target)
                .from(source)
                .using("browserify-#{name}-#{releaseType}")
            return [target]
    }
