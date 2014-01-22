# # Stylus Dependency Finder
#
# This tool can be used to compute the complete dependency list of a specific
# Stylus source file. It browses though the dependency chain created by the
# `@import` statements to establish the list.
#
# This script is needed by the Ninja build in order to recompile a Stylus
# asset whenever a dependency is modified. This is very important to ensure
# consistent minimal recompilation. See
# [configure.coffee](configure.coffee.html).
#
# Example usage:
#
#     $ coffee stylus-dep.coffee foo.styl --dep-file foo.css.d
#
'use strict'
_           = require 'lodash'
colors      = require 'colors'
commander   = require 'commander'
DepGraph    = require 'dep-graph'
fs          = require 'fs'
log         = require('yadsil')('stylus-dep')
path        = require 'path'

# Process CLI arguments and return the commander.js instance.
#
processCli = ->
    commander
        .usage('<file> [options]')
        .option('--color',             'force color display out of a TTY')
        .option('--dep-file <file>',   'output dependencies into a file')
        .parse(process.argv)
    log.color commander.color
    log.fatal 2, 'no enough file arguments' if commander.args.length < 1
    log.fatal 2, 'too many file arguments' if commander.args.length > 1
    commander

# Resolve a Stylus dependency path based on a `source` file path, and the
# path specified by the import clause, `importPath`, encountered in the
# source file. Return `null` is the target file can't be found, generating
# a log warning.
#
# For example, if a source file `src/foo.styl` imports a file
# `../lib/bar.styl`, the function will return `lib/bar.styl` if this file
# effectively exists.
#
# An imported path can be either a `css` or another `styl` file.
#
resolveImportPath = (source, importPath) ->
    dirName = path.dirname source
    basePath = path.join dirName, importPath
    for suffix in [ '.css', '.styl' ]
        fullpath = "#{basePath}#{suffix}"
        return fullpath if fs.existsSync fullpath
    log.warning "invalid import '#{importPath}' from '#{source}'"
    null

# Establish a list of direct dependencies of the Stylus file designated by
# `sourcePath`. Those can be other Stylus, or CSS files, and are determined
# by the import clauses. Return an array of the dependencies.
#
getDependenciesOf = (sourcePath) ->
    dependencies = []
    importRegex = /^@import (['"])([^\1\n]+)\1$/gm
    stylusStr = fs.readFileSync(sourcePath, 'utf-8')
    while match = importRegex.exec(stylusStr)
        depPath = resolveImportPath sourcePath, match[2]
        dependencies.push depPath if depPath?
    dependencies

# Entry point of the script. It builds a dependency graph by doing a
# [BFS](https://en.wikipedia.org/wiki/Breadth-first_search) on files imported
# from the specified file. Finally it writes the flattened dependency graph
# into a Makefile-compatible dependency file. For example, if `foo.styl`
# imports `bar.styl` and `bar.styl` imports `smth.css`:
#
#     foo.styl: bar.styl smth.css
#
do ->
    commander = processCli()
    sourcePath = commander.args[0]
    depFilePath = commander.depFile
    depGraph = new DepGraph
    nextPaths = [sourcePath]
    while nextPaths.length > 0
        depPath = nextPaths.shift()
        continue if path.extname(depPath) == '.css'
        newPaths = getDependenciesOf depPath
        _.forEach newPaths, (newDepPath) ->
            depGraph.add depPath, newDepPath
        nextPaths = nextPaths.concat newPaths
    chain = depGraph.getChain sourcePath
    deps = "#{sourcePath}: #{chain.join(' ')}\n"
    if depFilePath?
        fs.writeFileSync(depFilePath, deps)
        return
    process.stdout.write deps
