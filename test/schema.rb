ActiveRecord::Schema.define(:version => 0) do
  create_table :explicits, :force => true do |t|
    t.string   :original_filename, :null => false
    t.binary   :file_data
    t.text     :processing_log
    t.text     :results
    t.datetime :processed_at
  end

  create_table :implicits, :force => true do |t|
    t.string   :original_filename, :null => false
    t.binary   :file_data
    t.text     :processing_log
    t.text     :results
    t.datetime :processed_at
  end
  
  create_table :parents, :force => true do |t|
    t.text     :info
  end
  
  create_table :children, :force => true do |t|
    t.integer  :parent_id, :null => false
    t.text     :test_data
  end
  
  create_table :serializings, :force => true do |t|
    t.binary   :data
  end

  create_table :stis, :force => true do |t|
    t.string   :type
    t.string   :some_field
    t.binary   :big_field
  end
end