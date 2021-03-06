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

    ninja.assign 'node', 'node'

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
    factories.forActiveFactory config, log, (factory) ->
        if factory.makeRules
            log.debug "Making rules for #{factory.name}"
            factory.makeRules ninja, config

    makeSimpleRule ninja, {name: 'copy', command: 'cp $in $out'}
    makeSimpleRule ninja, {
        name: 'fingerprint'
        command: """
            $node #{findScript "fingerprint.js", config} $cliOptions -b $basePath -o $out $in
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
        if factories.getCoffeelintConfig().configFile?
            edge.need([factories.getCoffeelintConfig().configFile])

# Make all the edges necessary to compile assets, like Styluses, Coffees, etc.
# Assets are all contained into the root `/assets` folder.
#
makeAssetEdges = (ninja) ->
    # Note: the patterns with only lowercase `a-z` will ignore all caps files
    # such as `README.md`
    assetPaths = {}
    configNames = ['debug', 'release']
    for configName in configNames
        log.debug "Making #{configName} asset edges"
        assetPaths[configName] = []
        factories.forActiveFactory config, log, (factory) ->
            if factory.assetFiles and factory.makeAssetEdge
                log.debug "  #{factory.name}"
                mappingOptions = simpleMapOpt(
                    fp.assets,
                    path.join(fp.buildAssets, configName),
                    factory.targetExt or '.js')

                # Find the files we need to compile
                sourceFileNames = globule.find(factory.assetFiles, mappingOptions)

                # Generate edges for each file
                for match in globule.mapping(sourceFileNames, mappingOptions)
                    edges = factory.makeAssetEdge ninja, match.src, match.dest, configName
                    assetPaths[configName] = assetPaths[configName].concat edges

    ninja.edge('debug-assets').from(assetPaths.debug)

    if assetPaths.release.length > 0
        log.debug "Making fingerprint edge for #{assetPaths.release.length} release assets"
        fingerprintFile = makeFingerprintEdge ninja, assetPaths.release
        ninja.edge('release-assets').from(fingerprintFile)
    else
        # No assets means no fingerprint file is required.
        ninja.edge('release-assets')

# Make edges required for compiling everything in /src into /lib.
#
makeSourceEdges = (ninja) ->
    destFiles = []

    log.debug "Making src edges"
    factories.forActiveFactory config, log, (factory) ->
        if factory.files and factory.makeSrcEdge
            log.debug "  #{factory.name}"
            mappingOptions = simpleMapOpt('src', 'lib', factory.targetExt or '.js')

            # Find the files we need to compile
            sourceFileNames = globule.find(factory.files, mappingOptions)

            # Generate edges for each file
            for match in globule.mapping(sourceFileNames, mappingOptions)
                edges = factory.makeSrcEdge ninja, match.src, match.dest
                destFiles = destFiles.concat edges

    ninja.edge('lib').from(destFiles)

# Generate the edge in `ninja` to fingerprint assets.
#
makeFingerprintEdge = (ninja, assetsEdges) ->
    ninja.edge(fp.fingerprintFile).using('fingerprint')
         .from(assetsEdges)
         .assign('basePath', "#{fp.buildAssets}/release")
    fp.fingerprintFile

# Generate a proper `build.ninja` file for subsequent Ninja builds.
#
makeNinja = (options, done) ->

    ninja = ninjaBuilder('1.3', 'build')

    if options.disableStreamline
        log.warn 'disabling streamline as requested.'
        factories.filterFactories (factory) ->
            !(/streamline/i.test(factory.name))

    factories.forEachFactory (factory) ->
        factory.initialize?(ninja, config, log)

    ninja.header warnMessage
    ninja.assign 'cliOptions', '--color' if options.ninjaColor

    makeSystemEdges ninja, getOptionString(options), options
    makeCommonRules ninja, options

    if !options.noLint
        files = factories.getCoffeelintPaths()
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

    done null, ninja

# Build the option string that was used to run this instance of benbria-configure-ninja.
getOptionString = (options) ->
    str = ''
    str += ' --no-lint' if options.noLint
    str += ' --ninja-color' if options.ninjaColor
    str += ' --streamline8' if options.streamline8
    str += " --streamline-opts '#{options.streamlineOpts}'" if options.streamlineOpts
    str += ' --disable-streamline' if options.disableStreamline
    str += " --stylus-opts '#{options.stylusOpts}'" if options.stylusOpts
    str += " --require '#{options.require}'" if options.require
    return str


# Get configure options.
#
getOptions = ->
    ArgumentParser = require('argparse').ArgumentParser
    parser = new ArgumentParser
        version: packageJson.version
        addHelp: true
        description: """
            Generates a ninja.build file for a coffeescript project.
            """

    parser.addArgument [ '--require' ],
        help: "Comma delimited list of modules before building."
        nargs: "?"

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

    parser.addArgument [ '--disable-streamline' ],
        help: "Turn off streamline compiling completely"
        metavar: "opts"
        dest: "disableStreamline"
        action: 'storeTrue'

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
# `configureNinjaScript` is the full path to the binary to run to configure ninja.
#
module.exports = (configureNinjaScript) ->
    config.configureNinjaScript = configureNinjaScript

    options = getOptions()

    if options.streamline8 then config.streamlineVersion = 8
    config.streamlineOpts = options.streamlineOpts
    config.disableStreamline = options.disableStreamline
    config.stylusOpts = options.stylusOpts

    if options.require
        for mod in options.require.split(',')
            if mod.indexOf('./') == 0 then mod = path.resolve mod
            require mod

    makeNinja options, (err, ninja) ->
        throw err if err
        ninjaFile = path.resolve(config.ninjaFilePath, config.ninjaFile)
        ninja.save ninjaFile
        log.info "generated \'#{ninjaFile}\' (#{ninja.ruleCount} rules, #{ninja.edgeCount} edges)"
