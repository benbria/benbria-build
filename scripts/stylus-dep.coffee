# # Stylus Dependency Finder
#
# This tool can be used to compute the complete dependency list of a specific
# Stylus source file. It hooks into the Stylus compiler to see which
# files are included.
#
# This script is needed by the Ninja build in order to recompile a Stylus
# asset whenever a dependency is modified. This is very important to ensure
# consistent minimal recompilation. See
# [configure.coffee](configure.coffee.html).
#
# Accepts all the same arguments as the standard Stylus compiler, plus a
# --dep-file argument to specify the output of the dependency file.
#
# Example usage:
#
#     $ coffee stylus-dep.coffee foo.styl --dep-file foo.css.d
#
'use strict'

# Process arguments.
depFile = null
for arg, i in process.argv
    if arg == '--dep-file'
        depFile = process.argv[i+1]
        process.argv.splice(i, 2)
        break

inFile = null
deps = []

# Patch fs.readFile{,Sync} to see which files are read.
wrap = (obj, fn) ->
    oldFn = obj[fn]
    obj[fn] = (filename) ->
        if /\.(styl|css)$/.test filename
            if inFile?
                # Assume the input file is the first one to be read.
                deps.push filename
            else
                inFile = filename
        return oldFn.apply this, arguments

fs = require 'fs'
wrap fs, 'readFile'
wrap fs, 'readFileSync'

# Run the Stylus compiler.
require 'stylus/bin/stylus'

# After it's done, write the deps.
process.on 'exit', ->
    depString = "#{inFile}: #{deps.join ' '}"

    if depFile?
        fs.writeFileSync depFile, depString
    else
        process.stdout.write depString
