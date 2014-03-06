{spawn, exec} = require 'child_process'

build = (done) ->
    console.log "Building"
    exec './node_modules/.bin/coffee -m --compile --output lib/ src/', (err, stdout, stderr) ->
        process.stderr.write stderr
        return done err if err

        done?()

buildScripts = (done) ->
    console.log "Building scripts"
    exec './node_modules/.bin/coffee -m --compile --output lib/scripts/ scripts/', (err, stdout, stderr) ->
        process.stderr.write stderr
        return done err if err

        done?()

run = (fn) ->
    ->
        fn (err) ->
            console.log err.stack if err

task 'build', "Build project from src/*.coffee to lib/*.js", run build
task 'scripts', "Build project from scripts/*.coffee to lib/scripts/*.js", run buildScripts
