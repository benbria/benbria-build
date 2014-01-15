# This file contains a number of "factories" which describe how Ninja should process various kinds
# of files.  To define a new factory, call `defineFactory`, passing an type or an array of
# types, and a factory object.
#
# Types can be:
# * 'src' - Factories which will compile files in the 'src' directory into the 'lib' directory.
# * 'assets' - Factories which will compile assets.
# * 'generic' - Other factories.
#
# A factory is an object with one or more of the following properties:
# * `active` is either `true` or `false`, or else a `(config, log) ->` which returns `true` or
#   `false`.  Defaults to `true`.
# * `assignments(ninja, config)` should run any `ninja.assign()` calls required to setup the
#   factor.
# * `makeRules(ninja, config)` should run a `ninja.rule()` command for the rule name.  For src
#   rules, this should make a rule with the same name as the factory.  For asset rules, this
#   should make a `name-debug` and `name-release` rule.
# * `files` is an array of globule patterns which this factory will attempt to compile.  Patterns
#   are relative to /src for 'src' factories, and to /assets for 'assets' factories.
#   e.g. `['**/*._coffee']` for streamline coffee files.
# * `targetExt` is a string containing a target extension that files will compile to.  Defalts to
#   ".js"
# * `makeSrcEdge(ninja, source, target)` should make a ninja edge or edges required to build the
#   target file from the source file.  This is used for compiling files from "src" to "lib".
# * `makeAssetEdge(ninja, source, target, releaseType)` should make a ninja edge or edges required
#   to build the target file from the source file.  This is used for compiling assets.
#   `releaseType` will be either 'debug' or 'release'.
#

path = require 'path'
ld = require 'lodash'
{findCommandIfExists, findScript} = require './ninjaCommands'

getCommand = (config, log, commandName, desc) ->
    desc ?= commandName
    answer = findCommandIfExists commandName, config
    if !answer
        log.warn "#{commandName} not found - disabling #{desc} support."
    return answer

exports.factories = {}
allFactories = []

defineFactory = exports.defineFactory = (name, types, factory) ->
    if !ld.isArray types then types = [types]

    factory.name = name

    for type in types
        exports.factories[type] ?= {}
        exports.factories[type][name] = factory
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

# Run a command for every factory available.
exports.forActiveFactory = (config, log, fn) ->
    for type, factoryGroup of exports.factories
        for factoryName, factory of factoryGroup
            if isFactoryActive(factory, config, log)
                fn(factory)

# Coffee compiler
defineFactory "coffee", "src", {
    active: (config, log) ->
        if @_command is undefined
            @_command = getCommand config, log, 'coffee'
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
}

# JavaScript files are copied to their destination.
defineFactory "js", "src", {
    active: true
    files: '**/*.js'
    makeSrcEdge: (ninja, source, target) ->
        ninja.edge(target).from(source).using('copy')

}

# JS and Coffee streamline factories
makeStreamlineFactory = (name, ext, commandName) ->
    return {
        active: (config, log) ->
            if @_command is undefined
                @_command = getCommand config, log, commandName, name
            return @_command?

        assignments: (ninja, config) ->
            if config.streamlineVersion < 10
                ninja.assign name, "node --harmony #{@_command}"
            else
                ninja.assign name, @_command

        makeRules: (ninja, config) ->
            if config.streamlineVersion < 10
                # No source-maps for streamline.  You can add `--source-map $mapFile` here, but
                # streamline will often crash in 0.8.0.
                streamlineOpts = "-lp -c"
            else
                streamlineOpts = "-m -lp -c"

            ninja.rule(name)
                .run("$#{name} #{config.streamlineOpts} #{streamlineOpts} $in")
                .description "#{name.toUpperCase()} $in"

        files: "**/*#{ext}"
        makeSrcEdge: (ninja, source, target) ->
            targetDir = path.dirname target
            base = path.basename target, ".js"
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
    }

defineFactory "jsStreamline" , "src", makeStreamlineFactory('jsStreamline', '._js', '_node')
defineFactory "coffeeStreamline" , "src",
    makeStreamlineFactory('coffeeStreamline', '._coffee', '_coffee')

# Stylus compiler
defineFactory "stylus", "assets", {
    active: (config, log) ->
        if @_command is undefined
            @_command = getCommand config, log, 'stylus'
        return @_command?

    assignments: (ninja, config) ->
        ninja.assign 'stylus', @_command

    makeRules: (ninja, config) ->
        ['debug', 'release'].forEach (releaseType) ->
            cli = "$stylus $in -o $$(dirname $out) #{config.stylusOpts}"
            cli += if releaseType is 'release' then ' --compress' else ' --line-numbers'
            cli += " > /dev/null && $buildCoffee #{findScript "stylus-dep.coffee", config} $in"
            cli += ' --dep-file $out.d $cliOptions'

            ninja.rule("stylus-#{releaseType}")
                .run(cli)
                .depfile('$out.d')
                .description "(#{releaseType}) STYLUS $in"

    files: '**/[a-z0-9]*.styl'
    targetExt: '.css'

    makeAssetEdge: (ninja, source, target, releaseType) ->
        ninja.edge(target)
            .from(source)
            .using("stylus-#{releaseType}")

}

# Coffeelint tool
defineFactory "coffeelint", "generic", {
    active: (config, log) ->
        return !config.noLint

    assignments: (ninja, config) ->
        ninja.assign 'coffeelint', "$buildCoffee #{findScript "coffeelint.coffee", config}"

    makeRules: (ninja, config) ->
        ninja.rule("coffeelint")
            .run("$coffeelint $cliOptions -c .coffeelint $in && touch $out")
            .description "COFFEELINT $in"
}