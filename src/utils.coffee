# # Utility Library
#
# This library is useful for the project dev. and build scripts and provide
# the following features.
#
'use strict'
fs          = require 'fs'
crypto      = require 'crypto'

# ## Digest Computation
#
# Compute a quarter-of-MD5 digest of the file designated by `sourcePath` and
# call `callback` with `(error, digest)`.
#
exports.computeDigest = (sourcePath, callback) ->
    shasum = crypto.createHash('md5')
    stream = fs.ReadStream(sourcePath)
    stream.on 'error', (error) ->
        callback error
    stream.on 'data', (data) ->
        shasum.update data
    stream.on 'end', ->
        digest = shasum.digest('hex').substr(0, 8)
        callback null, digest
