ninjaFactories = require './ninjaFactories'
{findScript} = require './ninjaCommands'

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
                cli = "$buildCoffee #{findScript 'browserify-bundle.coffee'}"
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
