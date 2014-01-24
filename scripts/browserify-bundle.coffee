fs                  = require 'fs-extra'
path                = require 'path'
browserify          = require 'browserify'
i18nExtractor       = require 'i18n-extractor'
browserPackWithDeps = require 'browser-pack-with-deps'
ArgumentParser      = require('argparse').ArgumentParser
{minify}            = require 'uglify-js'


# Given a filename and source read from that file, writes "#{file}.i18n" with all string that
# need to be translated.
#
writeI18nFile = (file, source, done) ->
    # Write the translations file.
    warnings = []
    i18nExtractorOptions = {
        fun: new RegExp("^i18n$")
        key: 'i18n'
        init: {}
        warnings: warnings
    }
    result = i18nExtractor(source, i18nExtractorOptions)

    for warning in warnings
        console.log "WARNING: writing #{file} - #{warning}"

    answer = {i18n:[]}
    if result.i18n
        for key of result.i18n
            answer.i18n.push key
    fs.writeFile file, JSON.stringify(answer), (err) ->
        return done err if err
        done()

relativeToCwd = (file, basedir) ->
    if options.basedir
        file = path.resolve basedir, file
    return path.relative process.cwd(), file

# Write a gcc style dependencies file for the bundle.
#
# e.g. if you're compiling "start.coffee", which requires "bar.coffee" and "baz.coffee", this
# would write a file like:
#
#     start.coffee: bar.coffee baz.coffee
#
# Paths will be relative to the cwd.
#
writeDeps = (sourceFile, targetFile, deps, options, done) ->
    depsLine = "#{relativeToCwd sourceFile, options.basedir}:"
    for dep in deps
        depsLine += " #{relativeToCwd dep, options.basedir}"
    fs.writeFile targetFile, depsLine, done


# Builds a browserifyBundle.
#
# * `target` is the file that will be generated.
# * `sources` is an array of source files used as entry points for Browserify.
# * `options.browserifyOptions` will be passed as options to browserify's constructor.
# * If `options.debug` is true, then the target will not be minified, and will contain source maps.
# * `options.transforms` is a list of transforms to run on source files.
# * `done(err)` called when bundle has been built.
# * If `options.deps` is provided, then treated as a filename.  A gcc-style dependency file will be
#   written to this file.
# * If `options.i18n` is provided, then treated as a filename.  An object of i18n strings will
#   written to this file
#
exports.bundle = (target, sources, options, done) ->
    deps = []

    browserifyOptions = options.browserifyOptions or {}
    if options.deps
        origPack = browserifyOptions.pack
        browserifyOptions.pack = (params) ->
            params.raw = true
            params.sourceMapPrefix = '//#'
            answer = browserPackWithDeps params, origPack
            answer.on "dependency", (dep) ->
                deps.push dep
            return answer

    b = browserify(browserifyOptions)

    b.add source for source in sources
    b.transform(t) for t in (options.transforms ? [])

    bundleSourceCode = ""

    bundle = b.bundle({debug: !!options.debug})

    # Copy the source out to a string.
    bundle.on 'data', (data) -> bundleSourceCode += data
    bundle.on 'error', done
    bundle.on 'end', ->
        fs.mkdirs path.dirname(target), (err) ->
            return done err if err

            errored = null
            pending = 0
            doneHandler = (err) ->
                return if errored # Already called `done()`.
                errored ?= err
                pending--
                if errored or pending is 0 then done(errored)

                # TODO: If things fail, should we delete files that succeeded?

            # Write the bundle
            pending++
            if !options.debug
                minified = minify(bundleSourceCode, fromString: true)
                sourceToWrite = minified.code
            else
                sourceToWrite = bundleSourceCode
            fs.writeFile target, sourceToWrite, doneHandler


            # Write the dependencies file
            if options.deps
                pending++
                writeDeps sources[0], options.deps, deps, {basedir: browserifyOptions.basedir}, doneHandler

            if options.i18n
                pending++
                # Write the translations file.
                writeI18nFile options.i18n, bundleSourceCode, doneHandler

parseArgs = () ->
    parser = new ArgumentParser
        addHelp: true
        description: "Builds reporting.js"

    parser.addArgument [ '--debug' ],
        help: "Build debug files."
        nargs: 0
        action: 'storeTrue'

    parser.addArgument [ '--out', '-o' ],
        help: "Output file."
        nargs: "?"

    parser.addArgument [ '--deps', '-d' ],
        help: "Dependency output file (only works with --debug.)"
        nargs: "?"

    parser.addArgument [ '--i18n', '-i' ],
        help: "i18n output file."
        nargs: "?"

    parser.addArgument [ '--transforms', '-t' ],
        help: "Comma delimited list of transforms to run."

    parser.addArgument [ '--extensions', '-e' ],
        help: "List of extensions to require automatically."

    parser.addArgument [ 'input' ],
        help: "Files to compile."
        nargs: "+"

    args = parser.parseArgs()

    if !args.out
        parser.printUsage()
        console.log "error: --out required"
        process.exit 1

    return args

args = parseArgs()

options = {
    debug: args.debug
    i18n: args.i18n
    deps: args.deps
}
if args.transforms
    options.transforms = args.transforms.split(',').map (t) -> require t
if args.extensions
    options.browserifyOptions ?= {}
    options.browserifyOptions.extensions = args.extensions.split ','

start = new Date()
exports.bundle args.out, args.input, options, (err) ->
    if err
        console.log "Error while building #{args.out}", err.stack
        process.exit 1
    else
        console.log "Finished building #{args.out} in #{(new Date() - start)/1000} seconds"

