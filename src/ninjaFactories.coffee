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
ld = require 'lodash'
{findCommandIfExists, findScript, findLocalCommand} = require './ninjaCommands'

getCommand = (config, log, commandName, desc) ->
    desc ?= commandName
    answer = findCommandIfExists commandName, config
    if !answer
        log.warn "#{commandName} not found - disabling #{desc} support."
    return answer

exports.factories = {}
allFactories = []

defineFactory = exports.defineFactory = (name, factory) ->
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
exports.forActiveFactory = (config, log, options, fn) ->
    if !fn
        fn = options
        options = {}

    if options.type
        factoryList = ld.values exports.factories[options.type]
    else
        factoryList = allFactories

    for factory in factoryList
        if isFactoryActive(factory, config, log)
            fn(factory)

#
# /src factories
# --------------
#

# Coffee compiler
defineFactory "coffee", {
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
    makeAssetEdge: (ninja, source, target, releaseType) -> makeSrcEdge ninja, source, target

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
            makeAssetRule ninja, 'stylus', releaseType, cli

    assetFiles: '**/[a-z0-9]*.styl'
    targetExt: '.css'
    makeAssetEdge: makeAssetEdgeFn 'stylus'

}

# SASS compiler
defineFactory "sass", {
    assignments: (ninja, config) ->
        # TODO: Should detect existence of vendor/gem-bin-sass
        ninja.assign 'sass', 'vendor/gem-bin/sass'

    makeRules: (ninja, config) ->
        ['debug', 'release'].forEach (releaseType) ->
            cli = '$sass --compass $in $out'
            cli += if releaseType is 'release' then ' --style compressed' else ' --sourcemap'
            cli += " && ruby #{findScript "sass-dep.rb", config} $in > $out.d"
            makeAssetRule ninja, 'sass', releaseType, cli

    assetFiles: ['css/**/[a-z0-9]*.sass', 'css/**/[a-z0-9]*.scss']
    targetExt: '.css'
    makeAssetEdge: makeAssetEdgeFn 'sass'

}

# snockets compiler
defineFactory "snockets", {
    assignments: (ninja, config) ->
        ninja.assign 'snockets', findLocalCommand 'snockets', config

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

# template compiler
defineFactory "template", {
    makeRules: (ninja, config) ->
        ['debug', 'release'].forEach (releaseType) ->
            cli = "$buildCoffee #{findScript "template-cc.coffee", config} $in -o $out"
            cli += ' -i $out.i18n'
            cli += if (releaseType is 'release') then '' else ' -g'
            cli += ' -d $out.d $cliOptions'

            ninja.rule("template-#{releaseType}")
                .run(cli)
                .depfile('$out.d')
                .description "(#{releaseType}) TEMPLATE $folder"

    assetFiles: 'template/[a-z0-9]*'

    makeAssetEdge:  (ninja, source, target, releaseType) ->
        ninja.edge(target)
            .from(glob.sync("#{source}/[a-z0-9]*.jade"))
            .using("template-#{releaseType}")
            .assign('folder', source)
        return [target]
}

# releasenote compiler
defineFactory "releasenote", {
    initialize: (ninja, config, log) ->
        try
            includeFile = "assets/releasenote/INCLUDE.json"
            @includes = JSON.parse(fs.readFileSync(includeFile, 'utf8')).include
        catch err
            @includes = null

    active: (config, log) -> @includes != null

    makeRules: (ninja, config) ->
        ['debug', 'release'].forEach (releaseType) ->
            cli = "$buildCoffee #{findScript "template-cc.coffee", config} $in -o $out "
            cli += "-n $namespace -s Handlebars.releasenotes"
            cli += ' -i $out.i18n'
            cli += if (releaseType is 'release') then '' else ' -g'
            cli += ' -d $out.d $cliOptions'

            ninja.rule("releasenote-#{releaseType}")
                .run(cli)
                .depfile('$out.d')
                .description "(#{releaseType}) TEMPLATE $folder"

            concatCli = "$uglifyjs $in #{if (releaseType is 'release') then '' else '-b '}-o $out"
            ninja.rule("concat-#{releaseType}")
                .run(cli)
                .description "(#{releaseType}) CONCAT $folder"

        ninja.rule("json-merge")
            .run("$buildCoffee #{findScript "json-merge.coffee", config} $in -n -o $out")
            .description "JSON-MERGE $folder"

    assetFiles: 'releasenote/[a-z0-9]*.jade'
    targetExt: '.bare'

    makeAssetEdge:  (ninja, source, target, releaseType) ->
        # Make the releasenote template edge
        match = /\/releasenote\/([a-z]+)-.*\.jade/.exec(source)
        if !match
            throw new Error "[Ninja][Edge][ReleaseNote]: releasenote #{source} does not follow naming convention"

        ninja.edge(target)
            .from(source)
            .using("releasenote-#{releaseType}")
            .assign('namespace', match[1])

        # Create a dummy edge, since the template-cc creates two files,
        # the compiled js and its accompanying .i18n counterpart, ninja doesn't
        # actually have an edge for the .i18n. This means we cannot create other
        # edges that depend on it.
        ninja.edge(target + '.i18n')
            .from(source)
            .after(target)

        answer = [target, target + '.i18n']

        # Create edges that will concatenate the templates that every release note should have,
        # and the specific content templates, into one .js file. Also, concatenate the accompanying
        # .i18n files into one json file, as well.
        targetDir = path.dirname target
        includes = ld.map @includes, (file) -> path.join targetDir, file

        # We do not want to make a concatenated edge from the template file that is meant to be included.
        if !ld.contains includes, target
            includes.push target

            # we want to create a concatenated edge from some include templates,
            # and the main content edge
            concatTemplateFile = target.replace(/.bare/, '.doc.js')
            ninja.edge(concatTemplateFile)
                .from(includes)
                .using("concat-#{releaseType}")

            concatI18nFile = target.replace(/.bare/, '.doc.js.i18n')
            i18nIncludes = ld.map includes, (f) -> f += '.i18n'
            ninja.edge(concatI18nFile)
                .from(i18nIncludes)
                .using('json-merge')

            paths = [
                concatTemplateFile
                concatI18nFile
            ]

        return answer
}


# Coffeelint tool
defineFactory "coffeelint", {
    active: (config, log) ->
        return !config.noLint

    assignments: (ninja, config) ->
        ninja.assign 'coffeelint', "$buildCoffee #{findScript "coffeelint.coffee", config}"

    makeRules: (ninja, config) ->
        ninja.rule("coffeelint")
            .run("$coffeelint $cliOptions -c .coffeelint $in && touch $out")
            .description "COFFEELINT $in"
}