ninjaFactories  = require './ninjaFactories'
{findScript}    = require './ninjaCommands'
log             = require('yadsil')('index')

# Register a factory.  See ninjaFactories.coffee for details.
exports.defineFactory = ninjaFactories.defineFactory
exports.configureCoffeelint = ninjaFactories.configureCoffeelint

#
# * `sourceFile` is the entry file for browserify.
#   (e.g. "browserify/foo/foo.coffee")
# * `targetFile` is the js file to write, relative to `build/assets/{release|debug}/js`.  This will
#   automatically generate an i18n file and deps file. (e.g. "foo/foo.js")
# * `options.extensions` is a list of extensions to automatically require (e.g. ['.coffee'].)
# * `options.transform` is a list of transform names to use (e.g. ['coffeeify'].)
# * `options.insertGlobals` and `options.noparse` are the same as the Browserify equivalents.
# * `options.debugOnly` if this bundle should only be built for debug releaseType.
# * `options.releaseOnly` if this bundle should only be built for release releaseType.
#
exports.defineBrowserifyFactory = (name, sourceFile, targetFile, options) ->
    exports.defineFactory "browserify-#{name}", {
        makeRules: (ninja, config) ->
            ['debug', 'release'].forEach (releaseType) ->
                cli = "$node #{findScript 'browserify-bundle.js'}"
                if options.extensions then cli += " --extensions '#{options.extensions.join ","}'"
                # Alias `options.transforms` to `options.transform` to support older configs.
                transforms = options.transform ? options.transforms
                if transforms then cli += " --transforms '#{transforms.join ","}'"
                if options.insertGlobals then cli += " --insert-globals"
                for np in (options.noparse or [])
                    cli += " --noparse='#{np}'"
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
            return [] if options.debugOnly and (releaseType isnt 'debug')
            return [] if options.releaseOnly and (releaseType isnt 'release')

            target = "build/assets/#{releaseType}/js/#{targetFile}"
            ninja.edge(target)
                .from(source)
                .using("browserify-#{name}-#{releaseType}")
            return [target]
    }
