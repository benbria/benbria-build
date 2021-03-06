# This file contains a number of "factories" which describe how Ninja should process various kinds
# of files.  To define a new factory, call `defineFactory`, passing a name for the factory and
# an a factory object.
#
# A factory is an object with one or more of the following properties:
#
# * `active` is either `true` or `false`, or else a `(config, log) ->` which returns `true` or
#   `false`.  Defaults to `true`.
#
# * `initialize(ninja, config, log)` is called to setup the factory.
#
# * `assignments(ninja, config)` should run any `ninja.assign()` calls required to setup the
#   factor.
#
# * `makeRules(ninja, config)` should run a `ninja.rule()` command for the rule name.  For src
#   rules, this should make a rule with the same name as the factory.  For asset rules, this
#   should make a `name-debug` and `name-release` rule.
#
# * `targetExt` is a string containing a target extension that files will compile to.  Defalts to
#   ".js"
#
# * `files` is an array of globule patterns which this factory will attempt to compile.  Patterns
#   are relative to /src for 'src' factories. e.g. `['**/*._coffee']` for streamline coffee files.
#
# * `makeSrcEdge(ninja, source, target)` should make a ninja edge or edges required to build the
#   target file from the source file.  This is used for compiling files from "src" to "lib".
#   This will only be called if `files` is set. This should return a list of generated edge names.
#
# * `assetFiles` - Like `files`, but relative to /assets.  Used for asset edges.
#
# * `makeAssetEdge(ninja, source, target, releaseType)` should make a ninja edge or edges required
#   to build the target file from the source file.  This is used for compiling assets.
#   `releaseType` will be either 'debug' or 'release'.  This will only be called if `assetFiles` is
#   set.  This should return a list of generated edge names.
#
# The following properties will be added to the factory before any methods are called:
#
# * `config` - The configuration from build-configure-ninja.
# * `ninja` - The ninja instance being used.
# * `log` - A log to write to.
#
path = require 'path'
ld   = require 'lodash'
fs   = require 'fs'
log  = require('yadsil')('ninjaFactories')
glob = require 'glob'
_    = require 'lodash'
{findCommandIfExists, findScript, findLocalCommand} = require './ninjaCommands'

getCommand = (config, log, commandName, desc) ->
    desc ?= commandName
    answer = findCommandIfExists commandName, config
    if !answer
        log.warn "#{commandName} not found - disabling #{desc} support."
    return answer

allFactories = []

defineFactory = exports.defineFactory = (name, factory) ->
    factory.name = name
    allFactories.push factory

isFactoryActive = (factory, config, log) ->
    active = false
    if !factory.active
        active = true
    else
        if ld.isFunction factory.active
            active = factory.active config, log
        else
            active = factory.active

    return active

exports.forEachFactory = (fn) ->
    for factory in allFactories
        fn(factory)

# Run a filter fn on the factories to remove some
exports.filterFactories = (fn) ->
    allFactories = allFactories.filter fn

# Run a command for every factory available.
exports.forActiveFactory = (config, log, fn) ->
    for factory in allFactories
        if isFactoryActive(factory, config, log)
            fn(factory)

#
# /src factories
# --------------
#

# Coffee compiler
defineFactory "coffee", {
    initialize: (ninja, config, log) ->
        @_command = getCommand config, log, 'coffee'

    active: (config, log) ->
        return @_command?

    assignments: (ninja, config) ->
        ninja.assign 'coffee', @_command

    makeRules: (ninja, config) ->
        ninja.rule('coffee')
            .run('$coffee -c -m -o $outDir $in')
            .description 'COFFEE $in'

    files: ['**/*.coffee', '**/*.litcoffee', '**/*.coffee.md']

    makeSrcEdge: (ninja, source, target) ->
        ninja.edge(target)
            .from(source)
            .using('coffee')
            .assign('outDir', path.dirname target)
        return [target]
}

# JavaScript files are copied to their destination.
defineFactory "js", {
    active: true
    files: '**/*.js'
    assetFiles: 'js/**/[a-z0-9]*.js'
    makeSrcEdge: (ninja, source, target) ->
        ninja.edge(target).from(source).using('copy')
        return [target]
    makeAssetEdge: (ninja, source, target, releaseType) -> @makeSrcEdge ninja, source, target

}

# JS and Coffee streamline factories
makeStreamlineFactory = (name, ext, commandName) ->
    return {
        initialize: (ninja, config, log) ->
            @_command = getCommand config, log, commandName, name
            @oldStreamline = config.streamlineVersion < 10

        active: (config, log) ->
            return @_command?

        assignments: (ninja, config) ->
            if @oldStreamline
                ninja.assign name, "node --harmony #{@_command}"
            else
                ninja.assign name, @_command

        makeRules: (ninja, config) ->
            if @oldStreamline
                # No source-maps for streamline.  You can add `--source-map $mapFile` here, but
                # streamline will often crash in 0.8.0.
                streamlineOpts = "-lp -c"
            else
                streamlineOpts = "-m -o $outDir -f -c"

            ninja.rule(name)
                .run("$#{name} #{config.streamlineOpts} #{streamlineOpts} $in")
                .description "#{name.toUpperCase()} $in"

        files: "**/*#{ext}"

        makeSrcEdge: (ninja, source, target) ->
            targetDir = path.dirname target
            base = path.basename target, ".js"
            if @oldStreamline
                buildSource = path.join targetDir, "#{base}#{path.extname source}"
                mapFile = path.join targetDir, "#{base}.map"

                # Streamline only compiles files in-place, so make one edge to copy the
                # streamline file to the build dir...
                ninja.edge(buildSource).from(source).using("copy")

                # Make another edge to compile the file in the build dir.
                ninja.edge(target)
                    .from(buildSource)
                    .using(name)
                    .assign("mapFile", mapFile)
            else
                # New streamline (as of 0.10.9) supports the -o option.
                ninja.edge(target)
                    .from(source)
                    .using(name)
                    .assign('outDir', path.dirname target)
            return [target]
    }

defineFactory "jsStreamline" , makeStreamlineFactory('jsStreamline', '._js', '_node')
defineFactory "coffeeStreamline" ,
    makeStreamlineFactory('coffeeStreamline', '._coffee', '_coffee')

#
# /assets factories
# --------------
#

makeAssetRule = (ninja, name, releaseType, cli) ->
    ninja.rule("#{name}-#{releaseType}")
        .run(cli)
        .depfile('$out.d')
        .description "(#{releaseType}) #{name.toUpperCase()} $in"

makeAssetEdgeFn = (name) ->
    (ninja, source, target, releaseType) ->
        ninja.edge(target)
            .from(source)
            .using("#{name}-#{releaseType}")

        return [target]

# Stylus compiler
defineFactory "stylus", {
    initialize: (ninja, config, log) ->
        @_command = getCommand config, log, 'stylus'

    active: (config, log) ->
        return @_command?

    assignments: (ninja, config) ->
        ninja.assign 'stylus', @_command

    makeRules: (ninja, config) ->
        ['debug', 'release'].forEach (releaseType) ->
            cli = "$node #{findScript "stylus-dep.js", config} $in --print #{config.stylusOpts}"
            cli += if releaseType is 'release' then ' --compress' else ' --line-numbers'
            cli += ' --dep-file $out.d'
            cli += ' > $out'
            makeAssetRule ninja, 'stylus', releaseType, cli

    assetFiles: '**/[a-z0-9]*.styl'
    targetExt: '.css'
    makeAssetEdge: makeAssetEdgeFn 'stylus'

}

# snockets compiler
defineFactory "snockets", {
    initialize: (ninja, config, log) ->
        @_command = getCommand config, log, 'snockets'

    active: (config, log) ->
        return @_command?

    assignments: (ninja, config) ->
        ninja.assign 'snockets', @_command, config

    makeRules: (ninja, config) ->
        ['debug', 'release'].forEach (releaseType) ->
            cli = "$snockets $cliOptions $in -o $out --dep-file $out.d"
            cli += ' --minify' if releaseType is 'release'
            cli += " && #{findLocalCommand 'i18n-extract', config}"
            cli += ' -f \'(i18n)\' -k \'$$1\' $out > $out.i18n'

            makeAssetRule ninja, 'snockets', releaseType, cli

    assetFiles: 'js/**/[a-z0-9]*.coffee'
    makeAssetEdge: makeAssetEdgeFn 'snockets'

}

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
    configFile: null
}

setLintOptions = null

# Expose the option to override default coffeelint paths.
#
exports.configureCoffeelint = (options) ->
    setLintOptions = options

getCoffeelintConfig = exports.getCoffeelintConfig = -> return setLintOptions ? defaultLintOptions

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

exports.getCoffeelintPaths = ->
    collectCoffeeFiles getCoffeelintConfig()

# Collect all the coffee files to lint based on the currently set options
#
# Coffeelint tool
defineFactory "coffeelint", {
    active: (config, log) ->
        return !config.noLint

    assignments: (ninja, config) ->
        ninja.assign 'coffeelint', "$node #{findScript "coffeelint.js", config}"

    makeRules: (ninja, config) ->
        coffeelintConfigFile = getCoffeelintConfig().configFile
        coffeelintConfigFileOptions = if coffeelintConfigFile?
            "-c #{coffeelintConfigFile} "
        else
            ""

        ninja.rule("coffeelint")
            .run("$coffeelint $cliOptions #{coffeelintConfigFileOptions} $in && touch $out")
            .description "COFFEELINT $in"
}
