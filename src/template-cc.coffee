# # Template compiler
#
# This tool compiles template assets for client-side use. Those assets
# are a mix of two languages:
#
# * Jade, fully converted at compile-time;
# * Handlebars, precompiled for future client-side use.
#
# This setup allows Jade to reference server-side, compile-time variables
# provided by this compiler. Usage:
#
#     coffee template-cc.coffee foo.jade bar.jade > foobar.js
#
# This would for example generate two namespace `foo` and `bar`. By default
# they are put in a global object `Handlebars.templates`.
#
# File names that contains "-"s will be converted to camelCase.  For example,
# a file named "my-templates.jade" would generate the namespace "myTemplates".
#
# TODO: implement AMD declaration and use templates via Require.js.
#
'use strict'
_           = require 'lodash'
async       = require 'async'
colors      = require 'colors'
commander   = require 'commander'
DepGraph    = require 'dep-graph'
fs          = require 'fs'
glob        = require 'glob'
handlebars  = require 'handlebars'
jade        = require 'jade'
log         = require('yadsil')('template-cc')
{minify}    = require 'uglify-js'
path        = require 'path'

jadeDep     = require './jade-dep'

# Default global variable in which put the templates.
#
defaultStorage = 'Handlebars.templates'

# Process CLI arguments and return the commander.js instance.
#
processCli = ->
    commander
        .usage('<files> [options]')
        .option('--color',                  'force color display out of a TTY')
        .option('-v, --verbose',            'display processing details')
        .option('-d, --dep-file <path>',    'output dependencies into a file')
        .option('-i, --i18n-file <path>',   'output an i18n file')
        .option('-g, --debug',              'pretty-print the HTML & JS')
        .option('-o, --output <path>',      'output to a file')
        .option('-s, --storage <name>',
                'set the global var. storing templates', defaultStorage)
        .option('-n, --namespace <name>',    'choose the Handlebars.{namespace} instead of defaulting to `templates`.')
        .parse(process.argv)
    log.color commander.color
    log.verbose commander.verbose
    commander

lowerCaseWithDashesToCamelCase = (name) ->
    name.replace(/-(\S)/g, (v,x) -> x.toUpperCase())

# Build a helper function `i18n` to convert i18n server-side calls (in the
# Jade) into client-side calls (from Handlebars). The function object
# contains a `getTranslations` function returning the array of i18n strings.
#
# TODO: escape quotes in string.
#
buildI18n = ->
    translations = {}
    i18n = (string, args...) ->
        translations[string] = true
        "{{i18n \'#{string}\' #{args.join ' '}}}"
    i18n.getTranslations = ->
        _.map translations, (dummy, string) -> string
    i18n

# Take as input a string of just html attribute names and values. Parse them out into
# a hash. This is a very naive tokenizer, and assumes that the string will be a bunch of
# valid attribute names+values separated by spaces. This is probably fine for here, as the html frag we
# are getting has succesfully been compiled with jade. We could go futher and use/write a small html tokenizer.
# The regex was borrowed from jresig: http://ejohn.org/files/htmlparser.js
#
processAttributes = (rawAttrHTML) ->
    attrRegEx = /([-A-Za-z0-9_]+)(?:\s*=\s*(?:(?:"((?:\\.|[^"])*)")|(?:'((?:\\.|[^'])*)')|([^>\s]+)))?/g
    attrs = {}

    while match = attrRegEx.exec rawAttrHTML
        attrs["#{match[1]}"] = match[2]

    return attrs

# Process an HTML fragment containing one or more
# `<template id="foo"></template>` sections. Each section is extracted and
# precompiled as Handlebars code. It produces and returns JS code containing
# the templates. The resulting template function is also attached with some
# attributes, if they are present as part of the <template> tag.
#
processHTMLFragment = (fragment, namespace, progressCb) ->
    output = []
    output.push "  templates = storage.#{namespace} = {};\n"
    re = /\<template id=\"([^"]*)\"(.*?)\>([\s\S]*?)\<\/template\>/g
    while result = re.exec(fragment)
        progressCb result[1] if progressCb?
        attrs = processAttributes result[2]
        output.push "  templates['#{result[1]}'] = template(" \
                  + handlebars.precompile(result[3], {}) \
                  + ');\n\n'
        for attr, val of attrs
            output.push " templates['#{result[1]}']['#{attr}'] = '#{val}';"
    output.join('')

# Process a single Jade file, transformed into a namespace.
#
processSource = (sourcePath, namespace, jadeOptions, cbs, cb) ->
    namespace ?= lowerCaseWithDashesToCamelCase path.basename(sourcePath, '.jade')
    if cbs.template?
        innerProcessCb = (name) ->
            cbs.template namespace, name
    cbs.file sourcePath if cbs.file?
    jade.renderFile sourcePath, jadeOptions, (err, content) ->
        return cb err if err
        output = processHTMLFragment content, namespace, innerProcessCb
        cb(null, output)

# Process several template files, contained into the `folderPath` and call
# `cb(err, code)`.
#
processSources = (options, jadeOptions, cbs, cb) ->
    sourcePaths = options.args
    storage = options.storage
    namespace = options.namespace
    output = [
        '(function() {\n'
        '  var template = Handlebars.template;\n'
        "  if (#{storage} == null) #{storage} = {};\n"
        "  var templates, storage = #{storage};\n"
    ]
    processPath = (sourcePath, cb) ->
        processSource sourcePath, namespace, jadeOptions, cbs, (err, code) ->
            return cb err if err
            output.push code
            cb()
    async.eachSeries sourcePaths, processPath, (err) ->
        return cb err if err
        output.push '})();'
        cb(null, output.join(''))

# Write the i18n strings of `translations` into the file `filepath`.
#
write18File = (filepath, translations, isDebug) ->
    i18nInfo = {i18n: translations}
    json = JSON.stringify(i18nInfo, null, if isDebug then 2 else null)
    fs.writeFileSync filepath, json, 'utf8'

# Output the result.
#
processResult = (options, jadeOptions, code, deps) ->
    unless options.debug
        code = minify(code, {fromString: true}).code
    if options.i18nFile?
        write18File options.i18nFile, jadeOptions.i18n.getTranslations(),
                    options.debug
    if options.output?
        if options.depFile?
            fs.writeFileSync options.depFile,
                             "#{options.output}: #{deps.join(' ')}\n"
        return fs.writeFileSync options.output, code, 'utf8'
    process.stdout.write code

# Process the template file and output the result.
#
do ->
    options = processCli()

    # Always set pretty print to false.  Adding spaces between elements can cause/solve problems
    # so we do *not* want to pretty print in debug mode.  There is a world of difference between
    # `<div>a</div><div>b</div>` and `<div>a</div> <div>b</div>`, and pretty printing will
    # effectively turn everything into the second example.
    jadeOptions = {i18n: buildI18n(), pretty: false}

    deps = []
    cbs = {}
    cbs.template = (namespace, templateName) ->
        log.info 'processing: %s.%s', namespace, templateName
    if options.depFile?
        unless options.output?
            log.fatal 129, 'output must be specified when using --dep-file.'
        cbs.file = (sourcePath) ->
            deps = deps.concat jadeDep(sourcePath)
    processSources options, jadeOptions, cbs, (err, code) ->
        throw err if err
        processResult options, jadeOptions, code, deps
