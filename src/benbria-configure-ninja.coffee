# # Ninja Configuration Script
#
# This file drives the [Ninja](http://martine.github.io/ninja/) build process.
# Its purpose is to generate the Ninja input file, called `build.ninja` and
# located at the project root, by analysing the project structure. See the
# [Ninja manual](http://martine.github.io/ninja/manual.html) for more
# information about this file syntax.
#
# See this project's README.md for more details.

packageJson     = require '../package.json'
ld              = require 'lodash'
commander       = require 'commander'
fs              = require 'fs'
path            = require 'path'
glob            = require 'glob'
globule         = require 'globule'
log             = require('yadsil')('benbria-configure-ninja')
ninjaBuilder    = require 'ninja-build-gen'

factories       = require './ninjaFactories'
{findCommand, findLocalCommand, findScript} = require './ninjaCommands'

# Fix yadsil to behave like other logs
log.warn = log.warning

# Configuration
config = {}
config.ninjaFilePath = process.cwd()
config.ninjaFile = "build.ninja"
config.configureNinjaScript = __filename
config.streamlineVersion = 10
config.streamlineOpts = "" # --cb _cb
config.stylusOpts = ""

# Folder and file paths to use across the configuration.
fp = {}
fp.assets           = 'assets'
fp.build            = 'build'
fp.buildAssets      = "#{fp.build}/#{fp.assets}"
fp.coffeelint       = "#{fp.build}/coffeelint"
fp.fingerprintFile  = "#{fp.buildAssets}/release/fingerprints.json"

# Put on top of the generated Ninja manifest (`build.ninja`).
#
warnMessage = "# Auto-generated by `loop-configure-ninja`.\n"

# Generate the Ninja rule, and edge, which builds the `build.ninja` file itself.
# This edge is always executed first by Ninja, to ensure it has the lastest
# build graph. `optionString` should contain the arguments to call
# configure, supposed to stay the same as the original call.
#
makeSystemEdges = (ninja, optionString, options) ->
    ninja.assign 'buildCoffee', findLocalCommand('coffee', config)

    factories.forActiveFactory config, log, (factory) ->
        if factory.assignments
            log.debug "Generating assignments for #{factory.name}"
            factory.assignments ninja, config

    ninja.assign 'uglifyjs', findLocalCommand("uglifyjs", config)
    ninja.rule('configure')
         .run("#{findCommand('loop-configure-ninja', config)}#{optionString}")
         .description 'CONFIGURE'
    ninja.edge(config.ninjaFile)
        .using('configure')
        .need([findCommand('loop-configure-ninja', config)])

# Store the command line making functions.
#
makeCli = {}

# Make a SASS compilation command line.
#
makeCli.sass = (isRelease) ->
    # TODO: Need project-independent way to find sass.
    cli = 'vendor/gem-bin/sass --compass $in $out'
    cli += ' --sourcemap' unless isRelease
    cli += ' --style compressed' if isRelease
    cli += " && ruby #{findScript "sass-dep.rb", config} $in > $out.d"
    cli

# Make a Snockets compilation command line.
#
makeCli.snockets = (isRelease) ->
    cli = "#{findLocalCommand 'snockets', config} $cliOptions $in -o $out --dep-file $out.d"
    cli += ' --minify' if isRelease
    cli += " && #{findLocalCommand 'i18n-extract', config}"
    cli += ' -f \'(i18n)\' -k \'$$1\' $out > $out.i18n'
    cli

# Make a Template compilation command line.
#
makeCli.template = (isRelease) ->
    cli = "$buildCoffee #{findScript "template-cc.coffee", config} $in -o $out"
    cli += ' -i $out.i18n'
    cli += if isRelease then '' else ' -g'
    cli += ' -d $out.d $cliOptions'
    cli

# Make a Release compilation command line. The command is very similar
# to the Template command, with the addition of giving the `template-cc` script a
# `namespace` param
#
makeCli.releasenote = (isRelease) ->
    # TODO: template-cc.coffee should be compiled and run from node, so we don't need coffee installed.
    cli = "$buildCoffee #{findScript "template-cc.coffee", config} $in -o $out -n $namespace -s Handlebars.releasenotes"
    cli += ' -i $out.i18n'
    cli += if isRelease then '' else ' -g'
    cli += ' -d $out.d $cliOptions'
    cli


# Make a simple Ninja rule.
#
# * `name` - The name of the rule.  This is a free-form text string.
# * `command` - The command to run to compile files that use this rule.
# * `display` - `makeSimpleRule` will automatically provide a description for your rule of the
#   format `#{all-caps name} $in`.  If you provide a `display`, this will replace the "$in".
#   See [ninja docs on rule variables](http://martine.github.io/ninja/manual.html#ref_rule)
#   for a list of what can go here.
#
makeSimpleRule = (ninja, {name, command, display}) ->
    desc = name.toUpperCase() + ' ' + if display? then display else '$in'
    ninja.rule(name).run(command).description desc

# Add the *rules* used by diverse edges to build the project files. A rule is
# just a specification of 'how to compile A to B'. The following rules are
# defined:
#
# * `coffeelint`: Call the linter for CoffeeScript files.
# * `snockets`: Call the Snockets CoffeeScript compiler, generating a
#   dependency file at once, plus the i18n extractor.
#
# From ninjaFactories:
# * `coffee`: Call the simple CoffeeScript compiler.
# * `stylus`: Call the Stylus compiler, plus the dependency file generator.
# * `coffeeStreamline` and `jsStreamline`: Call the streamline compiler.
#
makeCommonRules = (ninja, options) ->
    assetTypes = ['snockets', 'sass', 'template', 'releasenote']
    assetTypes.forEach (ruleBaseName) ->
        ['debug', 'release'].forEach (releaseType) ->
            isTemplate = (ruleBaseName == 'template')
            rule = ninja.rule("#{ruleBaseName}-#{releaseType}")
            rule.run(makeCli[ruleBaseName](releaseType is 'release'))
                .depfile('$out.d')
                .description "(#{releaseType}) #{ruleBaseName.toUpperCase()}" \
                           + if isTemplate then ' $folder' else ' $in'

    factories.forActiveFactory config, log, (factory) ->
        if factory.makeRules
            log.debug "Making rules for #{factory.name}"
            factory.makeRules ninja, config

    makeSimpleRule ninja, {name: 'copy', command: 'cp $in $out'}
    makeSimpleRule ninja, {
        name: 'concat-debug'
        command: '$uglifyjs $in -b -o $out'
    }
    makeSimpleRule ninja, {
        name: 'concat-release'
        command: '$uglifyjs $in -o $out'
    }
    makeSimpleRule ninja, {
        name: 'json-merge'
        command: "$buildCoffee #{findScript "json-merge.coffee", config} $in -n -o $out"
    }
    makeSimpleRule ninja, {
        name: 'fingerprint'
        command: """
            $buildCoffee #{findScript "fingerprint.coffee", config} $cliOptions -b $basePath -o $out $in
        """
        display: '$basePath'
    }

# Generate a mapping using the 'globule' module, creating an edge for each
# file match. `mappingOptions` should be in the 'globule' format.
# `callback(edge)` is called for each created edge.
# Return an array of target files.
#
edgeMapping = (ninja, files, mappingOptions, callback) ->
    ld.map globule.mapping(files, mappingOptions), (match) ->
        callback ninja.edge(match.dest).from(match.src)
        match.dest

# Same as `edgeMapping`, but finding files from a pattern instead of being
# given by the caller.
#
edgeFindMapping = (ninja, patterns, mappingOptions, callback) ->
    files = globule.find(patterns, mappingOptions)
    edgeMapping(ninja, files, mappingOptions, callback)

# Create a simple mapping options object. This is a shorthand to avoid
# repeating the same option names over and over.
#
simpleMapOpt = (srcBase, destBase, ext) ->
    {srcBase, destBase, ext, extDot: 'last'}

# Make edges in `ninja` to lint the specified `coffeeFiles`.
# The generated '.coffeelint' are plain fake. They serve no other purpose
# than to say to Ninja "that fine, this file have been linted already, see
# there's a .coffeelint for it.".
#
# It's not 100% likeable but there's no real other solution with Ninja. We
# could be using Grunt or the coffeelint bin directly, but in this case it's
# not even incremental: everything would be relinted at each run.
#
makeLintEdges = (ninja, coffeeFiles) ->
    options = simpleMapOpt '.', '$builddir/coffeelint', '.coffeelint'
    edgeMapping ninja, coffeeFiles, options, (edge) ->
        edge.using('coffeelint')
            .need(['.coffeelint'])

# Make a typical asset-compilation mapping options object. `ext` is optional.
#
assetsMapOpt = (configName, ext) ->
    simpleMapOpt fp.assets, "#{fp.buildAssets}/#{configName}", ext

# Store the assets edge-making functions.
#
makeAssets = {}

# Make edges in `ninja` to compile Coffee (with Snockets) assets from
# `assets/js` to plain JS.
#
makeAssets.snockets = (ninja, patterns, configName) ->
    options = assetsMapOpt configName, '.js'
    edgeFindMapping ninja, patterns, options, (edge) ->
        edge.using("snockets-#{configName}")

# Make edges in `ninja` to copy simple assets.
#
makeAssets.copy = (ninja, patterns, configName) ->
    options = assetsMapOpt configName
    edgeFindMapping ninja, patterns, options, (edge) ->
        edge.using('copy')

# Make edges in `ninja` to compile Sass assets from `assets/sass` to CSS.
#
makeAssets.sass = (ninja, patterns, configName) ->
    options = simpleMapOpt "#{fp.assets}/css",
                           "#{fp.buildAssets}/#{configName}/css", '.css'
    edgeFindMapping ninja, patterns, options, (edge) ->
        edge.using("sass-#{configName}")
        # disabled for now, because Ninja complains:
        # "multiple outputs aren't (yet?) supported by depslog;
        #  bring this up on the mailing list if it affects you"
        # and depslog is more needed (for build speed).
        #   .produce("#{edge.targets[0]}.map")

# Make edges in `ninja` to compile template assets from `assets/template` to
# JS. Those edges are a bit special since each compile a whole folder content
# into a single JS file.
#
makeAssets.template = (ninja, patterns, configName) ->
    options = simpleMapOpt "#{fp.assets}/template",
                           "#{fp.buildAssets}/#{configName}/template", '.js'
    ld.map globule.findMapping(patterns, options), (match) ->
        ninja.edge(match.dest)
             .from(glob.sync("#{match.src[0]}/[a-z0-9]*.jade"))
             .using("template-#{configName}")
             .assign('folder', match.src[0])
        match.dest

# Make an edge that will compile the releasenote templates into a specific namespace.
#
makeReleaseNoteTemplateEdge = (ninja, configName, match) ->
    grabNamespace = new RegExp "#{fp.assets}/releasenote/([a-z]+)-.*\\.jade"
    namespace = grabNamespace.exec(match.src[0])
    unless namespace?
        throw new Error '[Ninja][Edge][ReleaseNote]: releasenote does not follow naming convention'
    namespace = namespace[1]

    templateEdge = match.dest
    i18nEdge = match.dest + '.i18n'

    ninja.edge(templateEdge)
        .from(match.src[0])
        .using("releasenote-#{configName}")
        .assign('namespace', namespace)

    # TODO: add the .i18n files to the ninja graph.
    # create a dummy edge, since the template-cc creates two files,
    # the compiled js and its accompanying .i18n counterpart, ninja doesn't
    # actually have an edge for the .i18n. This means we cannot create other
    # edges that depend on it
    ninja.edge(i18nEdge)
        .from(match.src[0])
        .after(templateEdge)

    paths = [
        templateEdge
        i18nEdge
    ]

# Create edges that will concatenate the templates that every release note should have, and the
# specific content templates, into one .js file. Also, concatenate the accompanying .i18n files into one
# json file, as well.
#
makeReleaseNoteConcatEdge = (ninja, configName, match) ->
    includeFile = "#{fp.assets}/releasenote/INCLUDE.json"
    includes = JSON.parse(fs.readFileSync(includeFile, 'utf8')).include
    includes = ld.map includes, (file) ->
        file = path.join "#{fp.buildAssets}/#{configName}/releasenote", file
    # we do not want to make a concatenated edge from the template file that is meant to be included.
    return null if ld.contains includes, match.dest
    bareTemplateEdge = match.dest
    concatTemplateEdge = match.dest.replace(/.bare/, '.doc.js')
    concati18nEdge = match.dest.replace(/.bare/, '.doc.js.i18n')

    # we want to create a concatenated edge from some include templates,
    # and the main content edge
    includes.push bareTemplateEdge
    ninja.edge(concatTemplateEdge)
        .from(includes)
        .using("concat-#{configName}")

    i18nIncludes = ld.map includes, (f) -> f += '.i18n'
    ninja.edge(concati18nEdge)
        .from(i18nIncludes)
        .using('json-merge')

    paths = [
        concatTemplateEdge
        concati18nEdge
    ]

# Make edges in `ninja` to compile templates specifically for releasenotes from
# `assets/releasenote`. These are special, as they need to be compiled from src->dest in a
# one-to-one manner. As well, their naming convention determines what namespace they will be put
# into in client-side js land. This lets client-side code grab only the release notes for particular apps.
#
makeAssets.releasenote = (ninja, patterns, configName) ->
    options = simpleMapOpt "#{fp.assets}/releasenote",
                           "#{fp.buildAssets}/#{configName}/releasenote", '.bare'
    ld.map globule.findMapping(patterns, options), (match) ->
        paths = []
        templatePaths = makeReleaseNoteTemplateEdge ninja, configName, match
        concatPaths = makeReleaseNoteConcatEdge ninja, configName, match
        paths = paths.concat templatePaths
        paths = paths.concat concatPaths if concatPaths?
        paths

# Make all the edges necessary to compile assets, like Styluses, Coffees, etc.
# Assets are all contained into the root `/assets` folder.
#
makeAssetEdges = (ninja) ->
    # Note: the patterns with only lowercase `a-z` will ignore all caps files
    # such as `README.md`
    assetPatterns = {
        sass        : ['**/[a-z0-9]*.sass', '**/[a-z0-9]*.scss']
        copy        : '**/[a-z0-9]*.js'
        snockets    : 'js/**/[a-z0-9]*.coffee'
        template    : '[a-z0-9]*'
        releasenote : '[a-z0-9]*.jade'
    }
    assetPaths = {}
    configNames = ['debug', 'release']
    for configName in configNames
        assetPaths[configName] = []
        for name, makeAsset of makeAssets
            paths = makeAsset(ninja, assetPatterns[name], configName)
            paths = if ld.isArray paths then paths else [paths]
            for p in paths
                assetPaths[configName] = assetPaths[configName].concat p

    for configName in configNames
        factories.forActiveFactory config, log, (factory) ->
            if factory.files and factory.makeAssetEdge
                log.debug "Making asset edges for #{configName} - #{factory.name}"
                mappingOptions = simpleMapOpt(
                    fp.assets,
                    path.join(fp.buildAssets, configName),
                    factory.targetExt or '.js')

                # Find the files we need to compile
                sourceFileNames = globule.find(factory.files, mappingOptions)

                # Generate edges for each file
                for match in globule.mapping(sourceFileNames, mappingOptions)
                    factory.makeAssetEdge ninja, match.src, match.dest, configName
                    assetPaths[configName].push match.dest

    ninja.edge('debug-assets').from(assetPaths.debug)
    if assetPaths.release.length > 0
        fingerprintFile = makeFingerprintEdge ninja, assetPaths.release
    ninja.edge('release-assets').from(fingerprintFile)

# Make edges required for compiling everything in /src into /lib.
#
makeSourceEdges = (ninja) ->
    destFiles = []

    factories.forActiveFactory config, log, (factory) ->
        if factory.files and factory.makeSrcEdge
            log.debug "Making src edges for #{factory.name}"
            mappingOptions = simpleMapOpt('src', 'lib', factory.targetExt or '.js')

            # Find the files we need to compile
            sourceFileNames = globule.find(factory.files, mappingOptions)

            # Generate edges for each file
            for match in globule.mapping(sourceFileNames, mappingOptions)
                factory.makeSrcEdge ninja, match.src, match.dest
                destFiles.push match.dest

    ninja.edge('lib').from(destFiles)

# Generate the edge in `ninja` to fingerprint assets.
#
makeFingerprintEdge = (ninja, assetsEdges) ->
    ninja.edge(fp.fingerprintFile).using('fingerprint')
         .from(assetsEdges)
         .assign('basePath', "#{fp.buildAssets}/release")
    fp.fingerprintFile

# Collect all the coffee files across the project.
#
# This is used for linting purposes.
#
collectCoffeeFiles = (ext, options) ->
    log.info 'looking for coffee script files..'
    coffeeFiles = [].concat \
        glob.sync("src/**/*.#{ext}"),
        glob.sync("assets/js/**/*.#{ext}"),
        glob.sync("bin/**/*.#{ext}"),
        glob.sync("Gruntfile.#{ext}")
    log.info "found #{coffeeFiles.length} #{ext} scripts"
    coffeeFiles

# Generate a proper `build.ninja` file for subsequent Ninja builds.
#
makeNinja = (options) ->
    ninja = ninjaBuilder('1.3', 'build')
    ninja.header warnMessage
    ninja.assign 'cliOptions', '--color' if options.ninjaColor

    makeSystemEdges ninja, getOptionString(options), options
    makeCommonRules ninja, options

    if !options.noLint
        files = collectCoffeeFiles('coffee', options).concat \
                collectCoffeeFiles('_coffee', options)
        ninja.edge('lint').from makeLintEdges(ninja, files)
    else
        # Make a dummy lint edge so we can still run 'ninja lint'.
        ninja.edge('lint')

    # Make 'debug-assets' and 'release-assets' edges.
    makeAssetEdges ninja

    # Make the 'lib' edge
    makeSourceEdges ninja

    # Make edges that people actually call into
    ninja.edge('debug').from(['debug-assets', 'lib'])
    ninja.edge('release').from(['release-assets', 'lib'])
    ninja.edge('all').from(['debug-assets', 'release-assets', 'lib'])
    ninja.byDefault 'all'

    return ninja

# Build the option string that was used to run this instance of benbria-configure-ninja.
getOptionString = (options) ->
    str = ''
    str += ' --no-lint' if options.noLint
    str += ' --ninja-color' if options.ninjaColor
    str += ' --streamline8' if options.streamline8
    str += " --streamline-opts '#{options.streamlineOpts}'" if options.streamlineOpts
    str += " --stylus-opts '#{options.stylusOpts}'" if options.stylusOpts
    return str


# Get configure options using commander.js.
#
getOptions = ->
    ArgumentParser = require('argparse').ArgumentParser
    parser = new ArgumentParser
        version: packageJson.version
        addHelp: true
        description: """
            Generates a ninja.build file for a coffeescript project.
            """

    parser.addArgument [ '--verbose' ],
        help: "Verbose output"
        nargs: 0

    parser.addArgument [ '--no-lint' ],
        help: "Disable coffee linting."
        dest: "noLint"
        nargs: 0

    parser.addArgument [ '--color' ],
        help: "Force color display out of a TTY."
        nargs: 0

    parser.addArgument [ '--ninja-color' ],
        help: "Force color on ninja scripts."
        dest: "ninjaColor"
        nargs: 0

    parser.addArgument [ '--streamline8' ],
        help: "Use streamline 0.8.x command line arguments (instead of 0.10.x)"
        nargs: 0

    parser.addArgument [ '--streamline-opts' ],
        help: "Extra options for streamline compilers"
        metavar: "opts"
        dest: "streamlineOpts"
        defaultValue: ''

    parser.addArgument [ '--stylus-opts' ],
        help: "Extra options for stylus"
        metavar: "opts"
        dest: "stylusOpts"
        defaultValue: ''

    # ***************************
    #
    # If you add arguments here, add them them to getOptionString() above, too!
    #
    # ***************************

    options = parser.parseArgs(process.argv[2..])

    if options.ninjaColor then options.color = true
    log.verbose options.verbose
    if options.color then log.color options.color

    if log.color()
        options.ninjaColor = true

    return options

# Entry point. Build the Ninja manifest and save it.
#
module.exports = (loopConfigureNinjaScript) ->
    config.configureNinjaScript = loopConfigureNinjaScript

    options = getOptions()

    if options.streamline8 then config.streamlineVersion = 8
    config.streamlineOpts = options.streamlineOpts
    config.stylusOpts = options.stylusOpts

    ninja = makeNinja(options)
    ninjaFile = path.resolve(config.ninjaFilePath, config.ninjaFile)
    ninja.save ninjaFile
    log.info "generated \'#{ninjaFile}\' (#{ninja.ruleCount} rules, #{ninja.edgeCount} edges)"
