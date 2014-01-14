# Simple command line tool to merge json files into one
#
'use strict'
_           = require 'lodash'
commander   = require 'commander'
fs          = require 'fs'
log         = require('yadsil')('json-merge')

DEFAULT_OUTPUT = './merged.json'

# Process CLI arguments and return the commander.js instance.
#
processCli = ->
    commander
        .usage('<files> [options]')
        .option('-o, --output <path>', 'output to a file')
        .option('-n, --nooverwrite', 'merge properties instead of overriding')
        .option('-v, --verbose', 'show more information on errors')
        .option('--color', 'force color display out of a TTY')
        .parse(process.argv)
    log.color commander.color
    commander

# Custom property merge function. It will merge arrays using `_.union` instead
# of overriding each other.
#
mergeProperties = (dest, src) ->
    if _.isArray(dest) and _.isArray(src)
        _.union dest, src
    else
        _.merge dest, src

# Merge one or more json files into one
#
mergeJson = (files, out, options) ->
    json = {}
    for file in files
        newJson = JSON.parse(fs.readFileSync(file, 'utf8'))
        callback = if options.nooverwrite then mergeProperties else null
        _.merge json, newJson, callback

    contents = JSON.stringify(json, null, null)
    err = fs.writeFileSync out, contents, 'utf8'
    if err
        return -1
    else
        return 1


# Entry point.
#
do ->
    options = processCli()
    outputPath = options.output or DEFAULT_OUTPUT
    okay = mergeJson(options.args, outputPath, {
        'nooverwrite' : if options.nooverwrite? then options.nooverwrite else false
    })
    unless okay
        process.exit 1
