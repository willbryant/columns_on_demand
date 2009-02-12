RAILS_ROOT = File.expand_path("../../..")
if File.exist?("#{RAILS_ROOT}/config/boot.rb")
  require "#{RAILS_ROOT}/config/boot.rb"
else
  require 'rubygems'
end

require 'test/unit'
require 'ruby-debug' rescue nil
require 'active_support'
require 'active_support/test_case'
require 'active_record'
require 'active_record/fixtures'

raise "use RAILS_ENV=mysql or RAILS_ENV=postgresql to test this plugin" if ENV['RAILS_ENV'].blank?
FileUtils.mkdir File.join(File.dirname(__FILE__), "log") rescue nil
RAILS_DEFAULT_LOGGER = ActiveRecord::Base.logger = Logger.new(File.join(File.dirname(__FILE__), "log", "#{ENV['RAILS_ENV']}.log"))

ActiveRecord::Base.configurations = YAML::load(IO.read(File.join(File.dirname(__FILE__), "database.yml")))
ActiveRecord::Base.establish_connection#(ActiveRecord::Base.configurations[ENV['RAILS_ENV']])
ActiveSupport::TestCase.fixture_path = File.join(File.dirname(__FILE__), "fixtures")

require 'init' # load columns_on_demand