path            = require 'path'
fs              = require 'fs'

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
#
# `options.ninjaFilePath` is the path to the build.ninja file being generated.
#
exports.findScript = (scriptName, options={}) ->
    # Look for this script in the scripts dir
    scriptsDir = path.resolve __dirname, path.join("..", "src")
    scriptFullPath = path.resolve scriptsDir, scriptName
    if !fs.existsSync scriptFullPath
        throw new Error("Could not find script #{scriptName}")

    if options.ninjaFilePath?
        answer = path.relative options.ninjaFilePath, scriptFullPath
    else
        answer = scriptFullPath

    return answer

# Finds a command.
#
# This will find a node_modules directory in the current directory or an ancestor of the current
# directory that contains ".bin/#{command}" and return the relative path to the command.
#
# Throws an exception if the command cannot be found.
#
# * `options.ninjaFilePath` is the path to the build.ninja file being generated.
# * `options.configureNinjaScript` is the full path to the loop-configure-ninja executable.
# * `options.fromDir` is the directory to start searching for the command in.  If not specified,
#   the search will start at `options.ninjaFilePath`.
#
exports.findCommand = (commandName, options={}) ->
    answer = exports.findCommandIfExists commandName, options
    if !answer then throw new Error("Could not find command #{commandName}")
    return answer

# Finds a command.
#
# This will find a node_modules directory in the current directory or an ancestor of the current
# directory that contains ".bin/#{command}" and return the relative path to the command.
#
# * `options.ninjaFilePath` is the path to the build.ninja file being generated.
# * `options.configureNinjaScript` is the full path to the loop-configure-ninja executable.
# * `options.fromDir` is the directory to start searching for the command in.  If not specified,
#   the search will start at `options.ninjaFilePath`.
#
exports.findCommandIfExists = (commandName, options={}) ->
    if commandName is "loop-configure-ninja" and options.configureNinjaScript?
        answer = options.configureNinjaScript
    else
        answer = null
        done = false
        currentDir = options.fromDir or options.ninjaFilePath
        if !currentDir? then throw new Error "Need option ninjaFilePath."

        while !answer and !done
            currentDir = parentDirSync currentDir, "node_modules"
            if currentDir == null
                done = true
            else
                commandFullPath = path.resolve currentDir, path.join("node_modules", ".bin", commandName)
                if fs.existsSync commandFullPath
                    answer = commandFullPath
                else
                    nextDir = path.resolve currentDir, '..'
                    if nextDir == currentDir then done = true
                    currentDir = nextDir

    if answer && options.ninjaFilePath?
        answer = path.relative options.ninjaFilePath, answer

    return answer


# Finds a command from this project's node_modules.
exports.findLocalCommand = (commandName, options={}) ->
    answer = path.resolve __dirname, path.join("..", "node_modules", ".bin", commandName)

    if fs.existsSync answer
        if options.ninjaFilePath?
            answer = path.relative options.ninjaFilePath, answer

    else
        # This can happen if the project which is requiring benbria-build already requires one
        # of our dependencies - the command will be in the parent project.
        answer = findCommand commandName, {
            ninjaFilePath: options.ninjaFilePath,
            configureNinjaScript: options.configureNinjaScript,
            fromDir: __dirname
        }

    return answer

