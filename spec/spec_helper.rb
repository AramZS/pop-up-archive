ENV["RAILS_ENV"] ||= 'test'

require 'simplecov'
require 'coveralls'

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
]
SimpleCov.start 'rails'

# require 'webmock'
# WebMock.disable_net_connect!(:allow_localhost => true)

require File.expand_path("../../config/environment", __FILE__)
require "rails/application"
require 'factory_girl'
require 'rspec/rails'
require 'rspec/mocks'
require 'capybara/rspec'
require 'capybara/rails'
require 'capybara/poltergeist'
require 'elasticsearch/extensions/test/cluster'
require 'database_cleaner'

DatabaseCleaner.strategy = :transaction

Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new(app, :browser => :chrome)
end

Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, :inspector => true)
end

Capybara.default_driver = :poltergeist

def create_es_index(klass)
  errors = []
  completed = 0
  puts "Creating Index for class #{klass}"
  klass.__elasticsearch__.create_index! force: true
  klass.__elasticsearch__.refresh_index!
  klass.__elasticsearch__.import  :return => 'errors', :batch_size => 200    do |resp|
    # show errors immediately (rather than buffering them)
    errors += resp['items'].select { |k, v| k.values.first['error'] }
    completed += resp['items'].size
    puts "Finished #{completed} items"
    STDERR.flush
    STDOUT.flush
    if errors.size > 0
      STDOUT.puts "ERRORS in #{$$}:"
      STDOUT.puts pp(errors)
    end
  end
  puts "Completed #{completed} records of class #{klass}"
end

def start_es_server
  Elasticsearch::Extensions::Test::Cluster.start(nodes: 1) unless Elasticsearch::Extensions::Test::Cluster.running?

  # indexes require data, but start clean.
  DatabaseCleaner.clean_with(:truncation)
  load Rails.root + "db/seeds.rb"

  # create index(s) to test against.
  create_es_index(Item)
end

def stop_es_server
  Elasticsearch::Extensions::Test::Cluster.stop if Elasticsearch::Extensions::Test::Cluster.running?
end

RSpec.configure do |config|
  config.include Capybara::DSL
  config.mock_with :rspec
  config.use_transactional_fixtures = true

  config.include Devise::TestHelpers, type: :controller
  Dir[Rails.root.join("spec/support/**/*.rb")].each {|f| require f }
  FactoryGirl.reload

  config.before :suite, elasticsearch: true do
    start_es_server
  end

  config.after :suite, elasticsearch: true do
    stop_es_server
  end

end

def test_file(ff)
  File.expand_path(File.dirname(__FILE__) + '/factories/files/' + ff)
end
