# # Ninja Configuration Script
#
# This file drives the [Ninja](http://martine.github.io/ninja/) build process.
# Its purpose is to generate the Ninja input file, called `build.ninja` and
# located at the project root, by analysing the project structure. See the
# [Ninja manual](http://martine.github.io/ninja/manual.html) for more
# information about this file syntax.
#
# Note that if you want to use coffee-script or streamline, you need to have them installed
# in your project, either as dependencies or dev-dependencies.  For streamline 0.8.x, you
# also need to pass `--streamline8` as an option.
#
# TODO: What are dependencies for stylus, sass, jade, handlebars?
#
# This will generate a ninja file with the following edges:
#
# * `build.ninja` - Re-run this target to pick up new files.
# * `lint` - Lint all source files.
# * `lib` - Compile all source files in /src to /lib.  This will automatically include:
#   * `*.js` - Copied directly over.
#   * `*.coffee`, `*.litcoffee`, `*.coffee.md` - Compiled to .coffee file.  Sourcemap will be
#     generated.
#   * `*._js`, `*._coffee` - Compiled with streamline compiler.  Souremaps will be generated if your
#     streamline compiler is v0.10.x or better.  Note you need to specify --streamline8 for
#     v0.8.x.  Lower than v0.8.x is not supported.
# * `debug-assets` - Build files in the assets folders.  Compiled files go into build/assets/debug.
#   Any files which start with an "_" will be excluded from the build:
#   * `assets/js/*.coffee`, `assets/js/*.js` - Javascript: These will be compiled with snockets support.
#   * `assets/*.sass`, `assets/*.scss`, `assets/*.styl` - CSS.
#   * `assets/template/*/*.jade` - Handlebars/jade templates.
#   * `assets/releasenote/*.jade` - Handlebars/jade templates.
# * `release-assets` - Same as `debug-assets` except compiled files go into build/assets/release.
#   Also this will run all files through the "fingerprint" process., producing a
#   build/release/fingerprints.json.
#
#
# ## Future improvements:
#
# * Should support streamline in /assets.
#

packageJson     = require '../package.json'
ld              = require 'lodash'
commander       = require 'commander'
fs              = require 'fs'
path            = require 'path'
glob            = require 'glob'
globule         = require 'globule'
log             = require('yadsil')('configure')
ninjaBuilder    = require 'ninja-build-gen'

config = {}
config.ninjaFilePath = process.cwd()
config.ninjaFile = "build.ninja"
config.configureNinjaScript = __filename
config.streamlineVersion = 10
config.extraStreamlineOpts = "" # --cb _cb

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

# Find the first parent directory of `dir` which contains a file named `fileToFind`.
parentDirSync = (dir, fileToFind) ->
    existsSync = fs.existsSync ? path.existsSync

    dirToCheck = path.resolve dir

    answer = null
    while true
        if existsSync path.join(dirToCheck, fileToFind)
            answer = dirToCheck
            break

        oldDirToCheck = dirToCheck
        dirToCheck = path.resolve dirToCheck, ".."
        if oldDirToCheck == dirToCheck
            # We've hit '/'.  We're done
            break

    return answer

# Returns the path to a script, relative to the directory we're writing the build.ninja file into.
findScript = (scriptName) ->
    # Look for this script in the scripts dir
    scriptsDir = path.resolve __dirname, "../src"
    scriptFullPath = path.resolve scriptsDir, scriptName
    if !fs.existsSync scriptFullPath
        throw new Error("Could not find script #{scriptName}")

    return path.relative config.ninjaFilePath, scriptFullPath

# Finds a command.
#
# This will find a node_modules directory in the current directory or an ancestor of the current
# directory that contains ".bin/#{command}" and return the relative path to the command.
#
findCommand = (command) ->
    if command is "loop-configure-ninja"
        answer = path.relative config.ninjaFilePath, config.configureNinjaScript
    else
        answer = null
        done = false
        currentDir = config.ninjaFilePath

        while !answer and !done
            currentDir = parentDirSync currentDir, "node_modules"
            if currentDir == null
                done = true
            else
                commandFullPath = path.resolve currentDir, "node_modules/.bin/#{command}"
                if fs.existsSync commandFullPath
                    answer = path.relative config.ninjaFilePath, commandFullPath
                else
                    nextDir = path.resolve currentDir, '..'
                    if nextDir == currentDir then done = true
                    currentDir = nextDir

        if done and !answer
            throw new Error("Could not find command #{command}")

    return answer



# Generate the Ninja rule, and edge, which builds the `build.ninja` file itself.
# This edge is always executed first by Ninja, to ensure it has the lastest
# build graph. `optionString` should contain the arguments to call
# configure, supposed to stay the same as the original call.
#
makeSystemEdges = (ninja, optionString, options) ->
    ninja.assign 'coffee', 'node_modules/.bin/coffee'
    if config.streamlineVersion < 10
        ninja.assign 'coffeeStreamline', "node --harmony #{findCommand '_coffee'}"
        ninja.assign 'jsStreamline', "node --harmony #{findCommand '_node'}"
    else
        ninja.assign 'coffeeStreamline', findCommand '_coffee'
        ninja.assign 'jsStreamline', findCommand '_node'
    ninja.assign 'uglifyjs', findCommand "uglifyjs"
    ninja.rule('configure')
         .run("$coffee #{findCommand('loop-configure-ninja')}#{optionString}")
         .description 'CONFIGURE'
    ninja.edge(config.ninjaFile)
        .using('configure')
        .need([
            findCommand('loop-configure-ninja'),
            # FIXME: call explicitly configure from task runner when
            #        a file have been added or removed
            '$builddir/config-puppet'])
    ninja.edge('$builddir/config-puppet')

# Store the command line making functions.
#
makeCli = {}

# Make a SASS compilation command line.
#
makeCli.sass = (isRelease) ->
    cli = 'vendor/gem-bin/sass --compass $in $out'
    cli += ' --sourcemap' unless isRelease
    cli += ' --style compressed' if isRelease
    cli += " && ruby #{findScript "sass-dep.rb"} $in > $out.d"
    cli

# Make a Snockets compilation command line.
#
makeCli.snockets = (isRelease) ->
    cli = 'node_modules/.bin/snockets $cliOptions' \
        + ' $in -o $out --dep-file $out.d'
    cli += ' --minify' if isRelease
    cli += ' && node_modules/.bin/i18n-extract'
    cli += ' -f \'(i18n)\' -k \'$$1\' $out > $out.i18n'
    cli

# Make a Stylus compilation command line.
#
makeCli.stylus = (isRelease) ->
    cli = 'node_modules/.bin/stylus $in -o $$(dirname $out) --import' \
        + ' node_modules/nib/index.styl'
    cli += if isRelease then ' --compress' else ' --line-numbers'
    cli += " > /dev/null && $coffee #{findScript "stylus-dep.coffee"} $in" \
         + ' --dep-file $out.d $cliOptions'
    cli

# Make a Template compilation command line.
#
makeCli.template = (isRelease) ->
    cli = "$coffee #{findScript "template-cc.coffee"} $in -o $out"
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
    cli = "$coffee #{findScript "template-cc.coffee"} $in -o $out -n $namespace -s Handlebars.releasenotes"
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
# * `coffeelint`: call the linter for CoffeeScript files;
# * `snockets`: call the Snockets CoffeeScript compiler, generating a
#   dependency file at once, plus the i18n extractor;
# * `coffee`: call the simple CoffeeScript compiler;
# * `stylus`: call the Stylus compiler, plus the dependency file generator.
#
makeCommonRules = (ninja, options) ->
    assetTypes = ['snockets', 'stylus', 'sass', 'template', 'releasenote']
    ld.forEach {debug: false, release: true}, (isRelease, config) ->
        ld.forEach assetTypes, (ruleBaseName) ->
            isTemplate = (ruleBaseName == 'template')
            rule = ninja.rule("#{ruleBaseName}-#{config}")
            rule.run(makeCli[ruleBaseName](isRelease))
                .depfile('$out.d')
                .description "(#{config}) #{ruleBaseName.toUpperCase()}" \
                           + if isTemplate then ' $folder' else ' $in'
    makeSimpleRule ninja, {
        name: 'coffeelint'
        command: """
            $coffee #{findScript "coffeelint.coffee"} $cliOptions -c .coffeelint $in && touch $out
            """
    }
    makeSimpleRule ninja, {
        name: 'coffee',
        command: '$coffee -c -m -o $outDir $in'
    }

    if config.streamlineVersion < 10
        # No source-maps for streamline.  You can add `--source-map $mapFile` here, but
        # streamline will often crash in 0.8.0.
        makeSimpleRule ninja, {
            name: 'coffeeStreamline',
            command: "$coffeeStreamline #{config.extraStreamlineOpts} -lp -c $in"
        }
        makeSimpleRule ninja, {
            name: 'jsStreamline',
            command: "$jsStreamline #{config.extraStreamlineOpts} -lp -c $in"
        }
    else
        makeSimpleRule ninja, {
            name: 'coffeeStreamline',
            command: "$coffeeStreamline #{config.extraStreamlineOpts} -m -lp -c $in"
        }
        makeSimpleRule ninja, {
            name: 'jsStreamline',
            command: "$jsStreamline #{config.extraStreamlineOpts} -m -lp -c $in"
        }

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
        command: "$coffee #{findScript "json-merge.coffee"} $in -n -o $out"
    }
    makeSimpleRule ninja, {
        name: 'fingerprint'
        command: """
            $coffee #{findScript "fingerprint.coffee"} $cliOptions -b $basePath -o $out $in
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
            .need(['.coffeelint', findScript("coffeelint.coffee")])

# Make phony edges in `ninja` to describe dependency of scripts upon
# `utils`. `utils` itself is target of a phony edge so that Ninja don't
# complain if we remove it at some point. The goal of these edges, of course,
# is to trigger recompilation if `utils` change.
#
makeScriptEdges = (ninja, shorthand, options) ->
    utilPath = findScript "utils.coffee"
    scripts = ['coffeelint', 'fingerprint', 'stylus-dep']
    paths = ld.map scripts, (script) ->
        scriptPath = findScript "#{script}.coffee"
        ninja.edge(scriptPath).need(utilPath)
        scriptPath
    ninja.edge(findCommand('loop-configure-ninja')).need(utilPath)
    paths.push findCommand('loop-configure-ninja')
    ninja.edge(utilPath)
    ninja.edge(shorthand).from(paths)
    paths

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

# Make edges in `ninja` to compile Stylus assets from `assets/css` to CSS.
#
makeAssets.stylus = (ninja, patterns, configName) ->
    options = assetsMapOpt configName, '.css'
    edgeFindMapping ninja, patterns, options, (edge) ->
        edge.using("stylus-#{configName}")
            .need(findScript "stylus-dep.coffee")

# Make edges in `ninja` to compile Sass assets from `assets/sass` to CSS.
#
makeAssets.sass = (ninja, patterns, configName) ->
    options = simpleMapOpt "#{fp.assets}/css",
                           "#{fp.buildAssets}/#{configName}/css", '.css'
    edgeFindMapping ninja, patterns, options, (edge) ->
        edge.using("sass-#{configName}").need(findScript "sass-dep.rb")
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
             .need(findScript "template-cc.coffee")
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
        .need(findScript "template-cc.coffee")
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
        .need(findScript "json-merge.coffee")
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
        stylus      : '**/[a-z0-9]*.styl'
        template    : '[a-z0-9]*'
        releasenote : '[a-z0-9]*.jade' # TODO: Why does this only pick up the release note files?
    }
    assetPaths = {}
    configNames = ['debug', 'release']
    ld.forEach configNames, (configName) ->
        assetPaths[configName] = []
        ld.forEach makeAssets, (makeAsset, name) ->
            paths = makeAsset(ninja, assetPatterns[name], configName)
            paths = if ld.isArray then paths else [paths]
            ld.forEach paths, (path) ->
                assetPaths[configName] = assetPaths[configName].concat path

    ninja.edge('debug-assets').from(assetPaths.debug)
    fingerprintFile = makeFingerprintEdge ninja, assetPaths.release
    ninja.edge('release-assets').from(fingerprintFile)

# Make edges required for compiling everything in /src into /lib.
#
makeSourceEdges = (ninja) ->
    makeStreamlineEdge = (ninja, source, target) ->
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
            .using(@rule)
            .assign("mapFile", mapFile)

    # `sources` is an array which describes how to build the various files in /src.
    # Parameters:
    # * `files` - A list of source files which should be processed by this object.
    # * `rule` - The ninja rule to use to compile these objects.
    # * `makeEdge(ninja, source, target)` - Optional.  Will be called to create a new
    #   ninja edge for your source file.  You must call `ninja.edge()` in this function.
    #   If this is specified, then `rule` is ignored.
    # * `targetExt` - The extension of the target file.  Defaults to '.js'.
    # * `sourceDir` - The base directory for source files.  Defaults to 'src'
    # * `targetDir` - The base directory for target files.  Defaults to 'lib'
    #
    sources = {
        coffee: {
            files: ['**/*.coffee', '**/*.litcoffee', '**/*.coffee.md']
            rule: 'coffee'
            makeEdge: (ninja, source, target) ->
                ninja.edge(target)
                    .from(source)
                    .using(@rule)
                    .assign('outDir', path.dirname target)
        }
        coffeeStreamline: {
            files: '**/*._coffee'
            rule: 'coffeeStreamline'
            makeEdge: makeStreamlineEdge
        }
        jsStreamline: {
            files: '**/*._js'
            rule: 'jsStreamline'
            makeEdge: makeStreamlineEdge
        }
        js: {
            files: '**/*.js'
            rule: 'copy'
        }
    }

    destFiles = []

    for name, source of sources
        mappingOptions = simpleMapOpt(
            source.sourceDir or 'src',
            source.targetDir or 'lib',
            source.targetExt or '.js')

        # Find the files we need to compile
        sourceFileNames = globule.find(source.files, mappingOptions)

        # Generate edges for each file
        globule.mapping(sourceFileNames, mappingOptions).forEach (match) ->
            if source.makeEdge
                source.makeEdge ninja, match.src, match.dest
            else
                ninja.edge(match.dest).from(match.src).using(source.rule)

            destFiles.push match.dest

    ninja.edge('lib').from(destFiles)

# Generate the edge in `ninja` to fingerprint assets.
#
makeFingerprintEdge = (ninja, assetsEdges) ->
    ninja.edge(fp.fingerprintFile).using('fingerprint')
         .from(assetsEdges).need(findScript "fingerprint.coffee")
         .need(findScript "utils.coffee")
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

# Build the option string provided to sub-commands.
#
getOptionString = (options) ->
    str = ''
    str += ' --no-lint' unless options.lint
    str += ' --ninja-color' if options.ninjaColor
    str += ' --streamline8' if options.streamline8
    str += " --streamline-args '#{options.streamlineArgs}'" if options.streamlineArgs
    str

# Generate a proper `build.ninja` file for subsequent Ninja builds.
#
makeNinja = (options) ->
    ninja = ninjaBuilder('1.3', 'build')
    ninja.header warnMessage
    ninja.assign 'cliOptions', '--color' if options.ninjaColor
    makeSystemEdges ninja, getOptionString(options), options
    makeCommonRules ninja, options
    makeScriptEdges ninja, 'scripts', options
    if options.lint
        files = collectCoffeeFiles('coffee', options).concat \
                collectCoffeeFiles('_coffee', options)
        ninja.edge('lint').from makeLintEdges(ninja, files)
    else
        ninja.edge('lint')
    makeAssetEdges ninja
    makeSourceEdges ninja
    ninja.edge('debug').from(['debug-assets', 'lib'])
    ninja.edge('release').from(['release-assets', 'lib'])
    ninja.edge('all').from(['debug-assets', 'release-assets', 'lib'])
    ninja.byDefault 'all'
    ninja

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

    parser.addArgument [ '--streamline-args' ],
        help: "Extra args for streamline compilers"
        metavar: "args"
        dest: "streamlineArgs"
        defaultValue: ''

    options = parser.parseArgs(process.argv[2..])
    options.lint = !options.noLint

    options.color = true if options.ninjaColor
    log.verbose options.verbose
    log.color options.color
    if log.color()
        options.ninjaColor = true

    options

# Entry point. Build the Ninja manifest and save it.
#
module.exports = (loopConfigureNinjaScript) ->
    config.configureNinjaScript = loopConfigureNinjaScript

    options = getOptions()

    if options.streamline8 then config.streamlineVersion = 8
    config.extraStreamlineOpts = options.streamlineArgs

    ninja = makeNinja(options)
    ninjaFile = path.resolve(config.ninjaFilePath, config.ninjaFile)
    ninja.save ninjaFile
    log.info "generated \'#{ninjaFile}\' (#{ninja.ruleCount} rules, #{ninja.edgeCount} edges)"
