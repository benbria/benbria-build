# Common build tools for Benbria projects

## build-configure-ninja

This script configures the [Ninja](http://martine.github.io/ninja/) build process.
Its purpose is to generate the Ninja input file, called `build.ninja` and
located at the project root, by analysing the project structure. See the
[Ninja manual](http://martine.github.io/ninja/manual.html) for more
information about this file syntax.

### Quick start

    npm install --save-dev git+ssh://git@github.com:benbria/benbria-build.git#v0.2.8
    npm install --save-dev ninja-build
    npm install --save-dev coffee-script
    npm install --save-dev [other optional dependencies - see below]
    mkdir src
    echo "console.log 'hello world'" > src/index.coffee
    ./node_modules/.bin/benbria-configure-ninja
    ./node_modules/.bin/ninja

### Project Layout

This assumes you have a project with the following file structure:

* /
  * /src - Server side source code goes here.  Every file here will be compiled into a .js and .map
    file in /lib.  This can include .js, .coffee, ._js, ._coffee.
  * /assets - Client side assets.  There are two different client side build types - debug and
    release.  Build artifacts will end up in /build/assets/debug or /build/assets/release,
    accordingly.
    * /assets/js - Client side source code.  This can include .js, .coffee.  coffee files can
      include snockets directives.  Any file that starts with an "_" will not be compiled - handy
      for files that are included via snockets and not used independently.
    * /assets/css - Client side CSS.  This can include .styl, .sass, .scss. (TODO: Would be nice if
      we copied .css files.)

### Dependencies

Your project should have any the following optional dependencies specified as dependencies or
devDependencies in it's project.json, and installed in the node_modules folder.  All of these are
optional; so long as you don't need the specified feature, you don't need them installed:

* coffee-script - Required for building .coffee files.
* streamline - Required for building ._js and ._coffee files in /src.  If you are
  using < 0.10.x, then make sure you pass `--streamline8` to `build-configure-ninja`.  You can also
  use `--streamline-opts '--cb _cb'` to set whatever extra streamline options you want.
* stylus - required for building .styl files.  You can use
  `--stylus-opts '--import node_modules/nib/index.styl'` to set arbitrary extra stylus options.

### Edges

This will generate a ninja file with the following edges:

* `build.ninja` - Re-run this target to pick up new files.

* `lint` - Lint all source files.

* `lib` - Compile all source files in /src to /lib.  This will automatically include:
  * `*.js` - Copied directly over.
  * `*.coffee`, `*.litcoffee`, `*.coffee.md` - Compiled to .coffee file.  Sourcemap will be
    generated.
  * `*._js`, `*._coffee` - Compiled with streamline compiler.  Souremaps will be generated if your
    streamline compiler is v0.10.x or better.  Note you need to specify --streamline8 for
    v0.8.x.  Lower than v0.8.x is not supported.

* `debug-assets` - Build files in the assets folders.  Compiled files go into build/assets/debug.
  Any files which start with an "_" will be excluded from the build:

  * `assets/js/*.coffee`, `assets/js/*.js` - Javascript: These will be compiled with snockets support.
  * `assets/*.sass`, `assets/*.scss`, `assets/*.styl` - CSS.

* `release-assets` - Same as `debug-assets` except compiled files go into build/assets/release.
  Also this will run all files through the "fingerprint" process., producing a
  build/release/fingerprints.json.

### Customizing the build

Build edges are generated by `factory` objects defined in src/ninjaFactories.coffee.  You can
define your own factories to customize your build process.  For example, to build a browserify
bundle as part of the build, create a file called `ninjaConfig.coffee`:

    {defineFactory} = require 'benbria-build'

    # Browserify bundle
    defineFactory "browserify-bundle", {
        makeRules: (ninja, config) ->
            ['debug', 'release'].forEach (releaseType) ->
                cli = "$buildCoffee ./assets/browserify/doBundle.coffee -o $out"
                cli += if (releaseType is 'release') then '' else ' --debug'

                ninja.rule("browserify-#{releaseType}")
                    .run(cli)
                    .description "(#{releaseType}) BROWSERIFY $in"

        assetFiles: 'browserify/src/main.coffee'

        makeAssetEdge:  (ninja, source, target, releaseType) ->
            target = "build/assets/#{releaseType}/js/main.js"
            ninja.edge(target)
                .from(source)
                .using("browserify-#{releaseType}")
            return [target]
    }

Then when you run benbria-configure-ninja:

    benbria-configure-ninja --require './ninjaConfig.coffee'

There's also built-in support for browserify:

    # Browserify bundle for reporting
    defineBrowserifyFactory "inbox",
        "browserify/inbox/inbox.coffee",
        "inbox/inbox.js", {
            extensions: ['.coffee', '.jade']
            transforms: [
                'coffeeify'
                'browserify-jade'
                'aliasify'
                'includify'
                'rfolderify'
                'debowerify'
            ]
        }

This will read assets/browserify/inbox/inbox.coffee, and compile it to
build/assets/[buildtype]/js/inbox/inbox.js.  i18n-extractor is automatically run on the output,
and in debug mode a dependencies file is built, so ninja will know whether or not your js file
needs rebuilding.


### Future improvements:

* Should support streamline in /assets.