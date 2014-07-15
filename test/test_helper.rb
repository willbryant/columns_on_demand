RAILS_ROOT = File.expand_path("../../..")
if File.exist?("#{RAILS_ROOT}/config/boot.rb")
  require "#{RAILS_ROOT}/config/boot.rb"
else
  require 'rubygems'
end

puts "Rails: #{ENV['RAILS_VERSION'] || 'default'}"
gem 'activesupport', ENV['RAILS_VERSION']
gem 'activerecord',  ENV['RAILS_VERSION']

require 'minitest/autorun'
require 'active_support'
require 'active_support/test_case'
require 'active_record'
require 'active_record/fixtures'

begin
  require 'ruby-debug'
  Debugger.start
rescue LoadError
  # ruby-debug not installed, no debugging for you
end

ActiveRecord::Base.configurations = YAML::load(IO.read(File.join(File.dirname(__FILE__), "database.yml")))
configuration = ActiveRecord::Base.configurations[ENV['RAILS_ENV']]
raise "use RAILS_ENV=#{ActiveRecord::Base.configurations.keys.sort.join '/'} to test this plugin" unless configuration
ActiveRecord::Base.establish_connection configuration

ActiveSupport::TestCase.send(:include, ActiveRecord::TestFixtures) if ActiveRecord.const_defined?('TestFixtures')
ActiveSupport::TestCase.fixture_path = File.join(File.dirname(__FILE__), "fixtures")

require File.expand_path(File.join(File.dirname(__FILE__), '../init')) # load columns_on_demand
