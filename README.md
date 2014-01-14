# Common build tools for Benbria projects

## build-configure-ninja

This script configures the [Ninja](http://martine.github.io/ninja/) build process.
Its purpose is to generate the Ninja input file, called `build.ninja` and
located at the project root, by analysing the project structure. See the
[Ninja manual](http://martine.github.io/ninja/manual.html) for more
information about this file syntax.

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
* jade - required for building .jade files.
* markdown - required for compiling markdown sections within jade files.
* handlebars - required for compiling handlebars templates.

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
  * `assets/template/*/*.jade` - Handlebars/jade templates.
  * `assets/releasenote/*.jade` - Handlebars/jade templates.
  * `release-assets` - Same as `debug-assets` except compiled files go into build/assets/release.

  Also this will run all files through the "fingerprint" process., producing a
  build/release/fingerprints.json.

### Future improvements:

* Should support streamline in /assets.