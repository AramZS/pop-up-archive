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
require 'capybara/rspec'
require 'capybara/rails'
require 'capybara/poltergeist'
require 'elasticsearch/extensions/test/cluster'
require 'elasticsearch/extensions/test/cluster'
# require 'webmock/rspec'

Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new(app, :browser => :chrome)
end

Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, :inspector => true)
end

Capybara.default_driver = :poltergeist

RSpec.configure do |config|
  config.include Capybara::DSL
  config.mock_with :rspec
  config.use_transactional_fixtures = true

  config.include Devise::TestHelpers, type: :controller
  Dir[Rails.root.join("spec/support/**/*.rb")].each {|f| require f }
  FactoryGirl.reload

  config.before :suite, elasticsearch: true do
    Elasticsearch::Extensions::Test::Cluster.start(nodes: 1) unless Elasticsearch::Extensions::Test::Cluster.running?
  end

  config.after :suite, elasticsearch: true do
    Elasticsearch::Extensions::Test::Cluster.stop if Elasticsearch::Extensions::Test::Cluster.running?
  end

end

def test_file(ff)
  File.expand_path(File.dirname(__FILE__) + '/factories/files/' + ff)
end
