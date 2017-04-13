require File.expand_path(File.join(File.dirname(__FILE__), 'test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), 'schema'))
require File.expand_path(File.join(File.dirname(__FILE__), 'activerecord_count_queries'))

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
    assert !record.column_loaded?(attr_name.to_s), "Record should not have the #{attr_name} column loaded, but did"
  end
  
  def assert_loaded(record, attr_name)
    assert record.column_loaded?(attr_name.to_s), "Record should have the #{attr_name} column loaded, but didn't"
  end
  
  def assert_queries(num = 1)
    ::SQLCounter.clear_log
    yield
  ensure
    assert_equal num, ::SQLCounter.log.size, "#{::SQLCounter.log.size} instead of #{num} queries were executed.#{::SQLCounter.log.size == 0 ? '' : "\nQueries:\n#{::SQLCounter.log.join("\n")}"}"
  end

  def assert_no_queries(&block)
    assert_queries(0, &block)
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
    assert_match(/\W*id\W*, \W*results\W*, \W*processed_at\W*/, Explicit.default_select(false))
    assert_match(/\W*explicits\W*.results/, Explicit.default_select(true))
    
    assert_match(/\W*id\W*, \W*original_filename\W*, \W*processed_at\W*/, Implicit.default_select(false))
    assert_match(/\W*implicits\W*.original_filename/, Implicit.default_select(true))
  end
  
  test "it doesn't load the columns_to_load_on_demand straight away when finding the records" do
    record = Implicit.first
    assert_not_equal nil, record
    assert_not_loaded record, "file_data"
    assert_not_loaded record, "processing_log"

    record = Implicit.all.to_a.first
    assert_not_equal nil, record
    assert_not_loaded record, "file_data"
    assert_not_loaded record, "processing_log"
  end
  
  test "it loads the columns when accessed as an attribute" do
    record = Implicit.first
    assert_equal "This is the file data!", record.file_data
    assert_equal "Processed 0 entries OK", record.results
    assert_equal record.results.object_id, record.results.object_id # should not have to re-find

    record = Implicit.all.to_a.first
    assert_not_equal nil, record.file_data
  end

  test "it loads the columns only once even if nil" do
    record = Implicit.first
    assert_not_loaded record, "file_data"
    assert_equal "This is the file data!", record.file_data
    assert_loaded record, "file_data"
    Implicit.update_all(:file_data => nil)

    record = Implicit.first
    assert_not_loaded record, "file_data"
    assert_nil record.file_data
    assert_loaded record, "file_data"
    assert_no_queries do
      assert_nil record.file_data
    end
  end
  
  test "it loads the column when accessed using read_attribute" do
    record = Implicit.first
    assert_equal "This is the file data!", record.read_attribute(:file_data)
    assert_equal "This is the file data!", record.read_attribute("file_data")
    assert_equal "Processed 0 entries OK", record.read_attribute("results")
    assert_equal record.read_attribute(:results).object_id, record.read_attribute("results").object_id # should not have to re-find
  end
  
  test "it loads the column when accessed using read_attribute_before_type_cast" do
    record = Implicit.first
    if Implicit.connection.class.name =~ /PostgreSQL/ && ActiveRecord::VERSION::MAJOR >= 4
      # newer versions of activerecord show the encoded binary format used for blob columns in postgresql in the before_type_cast output, whereas older ones had already decoded that
      assert_equal "\\x54686973206973207468652066696c65206461746121", record.read_attribute_before_type_cast("file_data")
    else
      assert_equal "This is the file data!", record.read_attribute_before_type_cast("file_data")
    end
    assert_equal "Processed 0 entries OK", record.read_attribute_before_type_cast("results")
    # read_attribute_before_type_cast doesn't tolerate symbol arguments as read_attribute does
  end
  
  test "it loads the column when generating #attributes" do
    attributes = Implicit.first.attributes
    assert_equal "This is the file data!", attributes["file_data"]
  end

  test "loads all the columns in one query when generating #attributes" do
    record = Implicit.first
    assert_queries(1) do
      attributes = record.attributes
      assert_equal "This is the file data!", attributes["file_data"]
      assert !attributes["processing_log"].blank?
    end
  end
  
  test "it loads the column when generating #to_json" do
    ActiveRecord::Base.include_root_in_json = true
    json = Implicit.first.to_json
    assert_equal "This is the file data!", ActiveSupport::JSON.decode(json)["implicit"]["file_data"]
  end
  
  test "it loads the column for #clone" do
    record = Implicit.first.clone
    assert_equal "This is the file data!", record.file_data

    record = Implicit.first.clone.tap(&:save!)
    assert_equal "This is the file data!", Implicit.find(record.id).file_data
  end
  
  test "it clears the column on reload, and can load it again" do
    record = Implicit.first
    old_object_id = record.file_data.object_id
    Implicit.update_all(:file_data => "New file data")

    record.reload

    assert_not_loaded record, "file_data"
    assert_equal "New file data", record.file_data
    assert_not_equal old_object_id, record.file_data.object_id
  end
  
  test "it doesn't override custom select() finds" do
    record = Implicit.select("id, file_data").first
    klass = ActiveRecord.const_defined?(:MissingAttributeError) ? ActiveRecord::MissingAttributeError : ActiveModel::MissingAttributeError
    assert_raise klass do
      record.processed_at # explicitly not loaded, overriding default
    end
    assert_loaded record, :file_data
  end

  test "it doesn't load the on demand columns with select *" do
    record = Implicit.select(Implicit.arel_table[Arel.star]).first
    assert_not_loaded record, "file_data"
    assert_not_loaded record, "processing_log"

    record = Implicit.select('*').first
    assert_not_loaded record, "file_data"
    assert_not_loaded record, "processing_log"
  end
  
  test "it raises normal ActiveRecord::RecordNotFound if the record is deleted before the column load" do
    record = Implicit.first
    Implicit.delete_all
    
    assert_raise ActiveRecord::RecordNotFound do
      record.file_data
    end
  end
  
  test "it doesn't raise on column access if the record is deleted after the column load" do
    record = Implicit.first
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

    assert_match(/\W*id\W*, \W*some_field\W*/, Dummy.default_select(false))

    ActiveRecord::Schema.define(:version => 2) do
      create_table :dummies, :force => true do |t|
        t.string   :some_field
        t.binary   :big_field
        t.string   :another_field
      end
    end

    assert_match(/\W*id\W*, \W*some_field\W*/, Dummy.default_select(false))
    Dummy.reset_column_information
    assert_match(/\W*id\W*, \W*some_field\W*, \W*another_field\W*/, Dummy.default_select(false))
  end
  
  test "it handles STI models" do
    class Sti < ActiveRecord::Base
      columns_on_demand
    end
    
    class StiChild < Sti
      columns_on_demand :some_field
    end

    assert_match(/\W*id\W*, \W*type\W*, \W*some_field\W*/, Sti.default_select(false))
    assert_match(/\W*id\W*, \W*type\W*, \W*big_field\W*/,  StiChild.default_select(false))
  end
  
  test "it works on child records loaded from associations" do
    parent = parents(:some_parent)
    child = parent.children.first
    assert_not_loaded child, "test_data"
    assert_equal "Some test data", child.test_data
  end
  
  test "it works on parent records loaded from associations" do
    child = children(:a_child_of_some_parent)
    parent = child.parent
    assert_not_loaded parent, "info"
    assert_equal "Here's some info.", parent.info
  end
  
  test "it works on child records loaded from associations with includes" do
    parent = Parent.includes(:children).first
    child = parent.children.first
    assert_not_loaded child, "test_data"
    assert_equal "Some test data", child.test_data
  end

  test "it works on parent records loaded from associations with includes" do
    child = Child.includes(:parent).first
    parent = child.parent
    assert_not_loaded parent, "info"
    assert_equal "Here's some info.", parent.info
  end

  test "it doesn't break validates_presence_of" do
    class ValidatedImplicit < ActiveRecord::Base
      self.table_name = "implicits"
      columns_on_demand
      validates_presence_of :original_filename, :file_data, :results
    end
    
    assert !ValidatedImplicit.new(:original_filename => "test.txt").valid?
    instance = ValidatedImplicit.create!(:original_filename => "test.txt", :file_data => "test file data", :results => "test results")
    instance.update_attributes!({}) # file_data and results are already loaded
    new_instance = ValidatedImplicit.find(instance.id)
    new_instance.update_attributes!({}) # file_data and results aren't loaded yet, but will be loaded to validate
  end
  
  test "it works with serialized columns" do
    class Serializing < ActiveRecord::Base
      columns_on_demand
      serialize :data
    end
    
    data = {:foo => '1', :bar => '2', :baz => '3'}
    original_record = Serializing.create!(:data => data)
    assert_equal data, original_record.data
    
    record = Serializing.first
    assert_not_loaded record, "data"
    assert_equal false, record.data_changed?

    assert_not_loaded record, "data"
    assert_equal data, record.data
    assert_equal false, record.data_changed?
    assert_equal false, record.changed?
    assert_equal data, record.data
    assert_equal data, record.data_was
    
    record.data = "replacement"
    assert_equal true, record.data_changed?
    assert_equal true, record.changed?
    record.save!
    
    record = Serializing.first
    assert_not_loaded record, "data"
    assert_equal "replacement", record.data
  end

  test "it doesn't create duplicate columns in SELECT queries" do
    implicits = Arel::Table.new(:implicits)
    reference_sql = implicits.project(implicits[:id]).to_sql
    select_sql = Implicit.select("#{Implicit.quoted_table_name}.#{Implicit.connection.quote_column_name("id")}").to_sql
    assert_equal select_sql, reference_sql
  end
end
