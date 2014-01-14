# # Coffeelint lean CLI
#
# This tool lints CoffeeScript files, using the coffee-lint library. There is
# an actual CLI provided with coffee-lint but it is way too verbose; it is
# targeted at processing lots of file at once (Grunt way). Since we are using
# Ninja to be incremental, we want minimal output, in the UNIX-style; as
# implemented here.
#
'use strict'
_           = require 'lodash'
coffeeLint  = require 'coffeelint'
commander   = require 'commander'
fs          = require 'fs'
log         = require('yadsil')('coffeelint')

# Process CLI arguments and return the commander.js instance.
#
processCli = ->
    commander
        .usage('<files> [options]')
        .option('-c, --config <file>', 'specify configuration file')
        .option('-v, --verbose', 'show more information on errors')
        .option('--color', 'force color display out of a TTY')
        .parse(process.argv)
    log.color commander.color
    commander

formatEntry = (filePath, entry) ->
    "#{filePath}:#{entry.lineNumber}: #{entry.message}"

# Process a single file for linting.
#
processFile = (filePath, lintOptions, options) ->
    okay = true
    try
        content = fs.readFileSync(filePath, 'utf8')
        result = coffeeLint.lint(content, lintOptions)
    catch error
        log.error "#{filePath}: #{error.message}"
        return false
    for entry in result
        if entry.level == 'error'
            log.error formatEntry(filePath, entry)
            okay = false
        else
            log.warning formatEntry(filePath, entry)
        continue unless options.verbose
        log.info "violates rule: #{entry.rule}"
        log.info entry.context if entry.context?
    okay

# Entry point.
#
do ->
    commander = processCli()
    lintOptions = null
    if commander.config
        lintOptions = JSON.parse(fs.readFileSync(commander.config, 'utf8'))
    okay = true
    for filePath in commander.args
        okay &= processFile(filePath, lintOptions, commander)
    unless okay
        process.exit 1
