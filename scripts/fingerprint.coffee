# # Fingerprints generator
#
# This script is used to generate asset fingerprints. This is useful for
# production only. Example: `js/foo.js` would be referenced by the
# fingerprinted URL `js/foo-12ab34cd.js`, `12ab34cd` being the beginning of
# the MD5 hash of the file. Usage:
#
#     coffee fingerprint.coffee foo.js bar.css -o fingerprints.json
#
# The generated JSON file is a map associating asset paths to their
# fingerprinted counterpart.
#
'use strict'
async       = require 'async'
commander   = require 'commander'
fs          = require 'fs'
log         = require('yadsil')('fingerprint')
path        = require 'path'
utils       = require './utils'

# Process CLI arguments and return the commander.js instance.
#
processCli = ->
    commander
        .usage('<asset files>')
        .option('-b, --base-path <path>', 'specify the path files are in')
        .option('-o, --output <path>', 'specify an output file instead of stdout')
        .option('--color', 'force color display out of a TTY')
        .parse(process.argv)
    log.color commander.color
    commander

# Make a fingerprinted path from a file path and the file content digest.
#
makeFpPath = (filePath, digest) ->
    ext = path.extname(filePath)
    baseName = filePath.substr(0, filePath.length - ext.length)
    "#{baseName}-#{digest}#{ext}"

# Process a file and add a corresponding entry into `fingerprints`.
#
processFile = (fingerprints, basePath, filePath, callback) ->
    unless filePath.substr(0, basePath.length) == basePath
        return callback(new Error("out of base path: #{filePath}"))
    virtualPath = filePath.substr(basePath.length)
    utils.computeDigest filePath, (error, digest) ->
        return callback(error) if error
        fingerprints[virtualPath] = makeFpPath(virtualPath, digest)
        callback()

# Entry point.
#
do ->
    commander = processCli()
    filePaths = commander.args
    fingerprints = {}
    okay = true
    basePath = commander.basePath ? ''
    forOne = (filePath, callback) ->
        processFile fingerprints, basePath, filePath, (err) ->
            if err
                log.error err.message
                okay = false
            callback()
    done = (error) ->
        log.fatal 1, error.message if error
        output = JSON.stringify(fingerprints, null, 2) + '\n'
        unless commander.output
            process.stdout.write output
        else
            fs.writeFileSync commander.output, output, 'utf8'
        process.exit 1 unless okay
    async.forEachSeries filePaths, forOne, done
