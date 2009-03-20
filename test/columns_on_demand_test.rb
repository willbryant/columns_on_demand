require 'test_helper'
require 'schema'

class Explicit < ActiveRecord::Base
  columns_on_demand :file_data, :processing_log, :original_filename
end

class Implicit < ActiveRecord::Base
  columns_on_demand
end

class Parent < ActiveRecord::Base
  columns_on_demand
  
  has_many :children
end

class Child < ActiveRecord::Base
  columns_on_demand
  
  belongs_to :parent
end

class ColumnsOnDemandTest < ActiveSupport::TestCase
  def assert_not_loaded(record, attr_name)
    assert_equal nil, record.instance_variable_get("@attributes")[attr_name.to_s]
  end
  
  fixtures :all
  self.use_transactional_fixtures = true
  
  test "it lists explicitly given columns for loading on demand" do
    assert_equal ["file_data", "processing_log", "original_filename"], Explicit.columns_to_load_on_demand
  end

  test "it lists all :binary and :text columns for loading on demand if none are explicitly given" do
    assert_equal ["file_data", "processing_log", "results"], Implicit.columns_to_load_on_demand
  end
  
  test "it selects all the other columns for loading eagerly" do
    assert_equal "id, results, processed_at", Explicit.default_select(false)
    assert_match /\W*explicits\W*.results/, Explicit.default_select(true)
    
    assert_equal "id, original_filename, processed_at", Implicit.default_select(false)
    assert_match /\W*implicits\W*.original_filename/, Implicit.default_select(true)
  end
  
  test "it doesn't load the columns_to_load_on_demand straight away when finding the records" do
    record = Implicit.find(:first)
    assert_not_equal nil, record
    assert_not_loaded record, "file_data"
    assert_not_loaded record, "processing_log"

    record = Implicit.find(:all).first
    assert_not_equal nil, record
    assert_not_loaded record, "file_data"
    assert_not_loaded record, "processing_log"
  end
  
  test "it loads the columns when accessed as an attribute" do
    record = Implicit.find(:first)
    assert_equal "This is the file data!", record.file_data
    assert_equal "Processed 0 entries OK", record.results
    assert_equal record.results.object_id, record.results.object_id # should not have to re-find

    record = Implicit.find(:all).first
    assert_not_equal nil, record.file_data
  end
  
  test "it loads the column when accessed using read_attribute" do
    record = Implicit.find(:first)
    assert_equal "This is the file data!", record.read_attribute(:file_data)
    assert_equal "This is the file data!", record.read_attribute("file_data")
    assert_equal "Processed 0 entries OK", record.read_attribute("results")
    assert_equal record.read_attribute(:results).object_id, record.read_attribute("results").object_id # should not have to re-find
  end
  
  test "it loads the column when generating #attributes" do
    attributes = Implicit.find(:first).attributes
    assert_equal "This is the file data!", attributes["file_data"]
  end
  
  test "it loads the column when generating #to_json" do
    json = Implicit.find(:first)
    assert_equal "This is the file data!", ActiveSupport::JSON.decode(json["file_data"])
  end
  
  test "it clears the column on reload, and can load it again" do
    record = Implicit.find(:first)
    old_object_id = record.file_data.object_id
    Implicit.update_all(:file_data => "New file data")

    record.reload

    assert_not_loaded record, "file_data"
    assert_equal "New file data", record.file_data
  end
  
  test "it doesn't override custom :select finds" do
    record = Implicit.find(:first, :select => "id, file_data")
    assert_raise ActiveRecord::MissingAttributeError do
      record.processed_at # explicitly not loaded, overriding default
    end
    assert_equal "This is the file data!", record.instance_variable_get("@attributes")["file_data"] # already loaded, overriding default
  end
  
  test "it raises normal ActiveRecord::RecordNotFound if the record is deleted before the column load" do
    record = Implicit.find(:first)
    Implicit.delete_all
    
    assert_raise ActiveRecord::RecordNotFound do
      record.file_data
    end
  end
  
  test "it doesn't raise on column access if the record is deleted after the column load" do
    record = Implicit.find(:first)
    record.file_data
    Implicit.delete_all
    
    assert_equal "This is the file data!", record.file_data # check it doesn't raise
  end
  
  test "it updates the select strings when columns are changed and the column information is reset" do
    ActiveRecord::Schema.define(:version => 1) do
      create_table :dummies, :force => true do |t|
        t.string   :some_field
        t.binary   :big_field
      end
    end

    class Dummy < ActiveRecord::Base
      columns_on_demand
    end

    assert_equal "id, some_field", Dummy.default_select(false)

    ActiveRecord::Schema.define(:version => 2) do
      create_table :dummies, :force => true do |t|
        t.string   :some_field
        t.binary   :big_field
        t.string   :another_field
      end
    end

    assert_equal "id, some_field", Dummy.default_select(false)
    Dummy.reset_column_information
    assert_equal "id, some_field, another_field", Dummy.default_select(false)
  end
  
  test "it handles STI models" do
    ActiveRecord::Schema.define(:version => 1) do
      create_table :stis, :force => true do |t|
        t.string   :type
        t.string   :some_field
        t.binary   :big_field
      end
    end

    class Sti < ActiveRecord::Base
      columns_on_demand
    end
    
    class StiChild < Sti
      columns_on_demand :some_field
    end

    assert_equal "id, type, some_field", Sti.default_select(false)
    assert_equal "id, type, big_field",  StiChild.default_select(false)
  end
  
  test "it works on child records loaded from associations" do
    parent = parents(:some_parent)
    child = parent.children.find(:first)
    assert_not_loaded child, "test_data"
    assert_equal "Some test data", child.test_data
  end
  
  test "it works on parent records loaded from associations" do
    child = children(:a_child_of_some_parent)
    parent = child.parent
    assert_not_loaded parent, "info"
    assert_equal "Here's some info.", parent.info
  end
end
