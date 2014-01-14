# # Jade Dependencies
#
# This module provides a mean to find the complete list of a Jade file
# dependencies. It browses the dependency chain created by the `include`
# or `extends` statements to do so.

'use strict'
_           = require 'lodash'
DepGraph    = require 'dep-graph'
fs          = require 'fs'
path        = require 'path'

# Resolve a dependency path based on a `source` file path, and the
# path specified by the import clause, `importPath`, encountered in the
# source file. Return `null` if the target file can't be found.
#
# For example, if a source file `src/foo.jade` includes a `../lib/bar`, the
# function will return `lib/bar.jade` if this file effectively exists.
resolveImportPath = (source, importPath) ->
    dirName = path.dirname source
    basePath = path.join dirName, importPath
    fullpath = "#{basePath}.jade"
    return fullpath if fs.existsSync fullpath
    null

# Establish a list of direct dependencies of the file designated by
# `sourcePath`. Those can be other Jade files and are determined by the
# `include` clauses. Return the array of dependencies as strings.
# `cbBroken(sourcePath, includePath)` is called whenever an invalid include is
# encountered.
getDependenciesOf = (sourcePath, cbBroken) ->
    dependencies = []
    importRegex = /^(?:extends|include) ([^\n]+)$/gm
    code = fs.readFileSync(sourcePath, 'utf-8')
    while match = importRegex.exec(code)
        depPath = resolveImportPath sourcePath, match[1]
        unless depPath?
            cbBroken(sourcePath, match[1]) if cbBroken?
            continue
        dependencies.push depPath
    dependencies

# Build a dependency graph by doing a
# [BFS](https://en.wikipedia.org/wiki/Breadth-first_search) on files imported
# from the specified file. Return the flattened dependency list, being an array
# of file paths (strings). The optional function `cbBroken(sourcePath,
# includePath)` is called whenever an invalid import is encountered.
module.exports = (sourcePath, cbBroken) ->
    depGraph = new DepGraph
    nextPaths = [sourcePath]
    while nextPaths.length > 0
        depPath = nextPaths.shift()
        newPaths = getDependenciesOf depPath, cbBroken
        _.forEach newPaths, (newDepPath) ->
            depGraph.add depPath, newDepPath
        nextPaths = nextPaths.concat newPaths
    depGraph.getChain sourcePath
