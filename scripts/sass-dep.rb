# # SASS dependency finder
#
# This script catches the dependencies of a single SASS file using the offical
# SASS Ruby library, and stdout-put them in a Makefile-compatible format.
# Inspired from https://gist.github.com/chrisirhc/4704595. Note that the
# library raises an exception in case of invalid imports.
#
require 'rubygems'
require 'bundler/setup'

require 'sass'
require 'compass'
require 'pathname'

sassFilePath = ARGV[0]
options = Compass.sass_engine_options
if ARGV.length > 1
    options[:load_paths] << ARGV[1]
end

# Collect dependencies.
sassEngine = Sass::Engine.for_file(sassFilePath, options)
deps = sassEngine.dependencies.collect! {|dep| dep.options[:filename]}

# Keep only dependencies that are in the project.
projectPath = Pathname.getwd().join 'assets/css'
deps = deps.find_all{|path|
    not Pathname.new(path).expand_path
                .relative_path_from(projectPath).to_s.start_with? '..'
}

# Write the Makefile-compatible dependency file on stdout.
$stdout.write sassFilePath + ": "
$stdout.write deps.to_a().join(" ")
$stdout.write "\n"
