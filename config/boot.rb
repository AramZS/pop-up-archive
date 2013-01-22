require 'rubygems'

# Set up the environment
ENV['ENV_OVERRIDE_FILE'] ||= File.expand_path('../env_vars', __FILE__)

if File.exists?(ENV['ENV_OVERRIDE_FILE'])
  File.open(ENV['ENV_OVERRIDE_FILE']) do |file|
    while line = file.gets
      line.chomp!
      var, val = line.split('=', 2)
      ENV[var] = val
    end
  end
end

# Set up gems listed in the Gemfile.
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../Gemfile', __FILE__)

require 'bundler/setup' if File.exists?(ENV['BUNDLE_GEMFILE'])

