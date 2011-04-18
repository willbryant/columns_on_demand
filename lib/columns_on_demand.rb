module ColumnsOnDemand
  module BaseMethods
    def columns_on_demand(*columns_to_load_on_demand)
      class_inheritable_accessor :columns_to_load_on_demand, :instance_writer => false
      self.columns_to_load_on_demand = columns_to_load_on_demand.empty? ? blob_and_text_columns : columns_to_load_on_demand.collect(&:to_s)

      extend ClassMethods
      include InstanceMethods

      if ActiveRecord::VERSION::MAJOR > 2
        relation # set up @relation
        class << @relation # but always modify @relation, not the temporary returned by .relation if there's a where(type condition)
          def build_select_with_columns_on_demand(arel, selects)
            unless selects.empty?
              build_select_without_columns_on_demand(arel, selects)
            else
              arel.project(Arel::SqlLiteral.new(@klass.default_select(true)))
            end
          end
          alias_method_chain :build_select, :columns_on_demand
        end
      end
      
      class <<self
        alias_method_chain :reset_column_information,        :columns_on_demand
      end
      alias_method_chain   :attribute_names,                 :columns_on_demand
      alias_method_chain   :read_attribute,                  :columns_on_demand
      alias_method_chain   :read_attribute_before_type_cast, :columns_on_demand
      alias_method_chain   :unserialize_attribute,           :columns_on_demand
      alias_method_chain   :missing_attribute,               :columns_on_demand
      alias_method_chain   :reload,                          :columns_on_demand
    end
    
    def reset_column_information_with_columns_on_demand
      @columns_to_select = nil
      reset_column_information_without_columns_on_demand
    end
    
    def blob_and_text_columns
      columns.inject([]) do |blob_and_text_columns, column|
        blob_and_text_columns << column.name if column.type == :binary || column.type == :text
        blob_and_text_columns
      end
    end
  end
  
  module ClassMethods
    # this is the method API as called by ActiveRecord 2.x.  we also call it ourselves above in our ActiveRecord 3 extensions.
    def default_select(qualified)
      @columns_to_select ||= (columns.collect(&:name) - columns_to_load_on_demand).collect {|attr_name| connection.quote_column_name(attr_name)}
      if qualified
        quoted_table_name + '.' + @columns_to_select.join(", #{quoted_table_name}.")
      else
        @columns_to_select.join(", ")
      end
    end
  end
  
  module InstanceMethods
    def attribute_names_with_columns_on_demand
      (attribute_names_without_columns_on_demand + columns_to_load_on_demand).uniq.sort
    end
    
    def load_attributes(*attr_names)
      values = connection.select_rows(
        "SELECT #{attr_names.collect {|attr_name| connection.quote_column_name(attr_name)}.join(", ")}" +
        "  FROM #{self.class.quoted_table_name}" +
        " WHERE #{connection.quote_column_name(self.class.primary_key)} = #{quote_value(id, self.class.columns_hash[self.class.primary_key])}")
      row = values.first || raise(ActiveRecord::RecordNotFound, "Couldn't find #{self.class.name} with ID=#{id}")
      attr_names.each_with_index {|attr_name, i| @attributes[attr_name] = row[i]}
    end
    
    def ensure_loaded(attr_name)
      load_attributes(attr_name.to_s) unless @attributes.has_key?(attr_name.to_s) || !columns_to_load_on_demand.include?(attr_name.to_s)
    end
    
    def read_attribute_with_columns_on_demand(attr_name)
      ensure_loaded(attr_name)
      read_attribute_without_columns_on_demand(attr_name)
    end

    def read_attribute_before_type_cast_with_columns_on_demand(attr_name)
      ensure_loaded(attr_name)
      read_attribute_before_type_cast_without_columns_on_demand(attr_name)
    end

    def unserialize_attribute_with_columns_on_demand(attr_name)
      ensure_loaded(attr_name)
      unserialize_attribute_without_columns_on_demand(attr_name)
    end

    def missing_attribute_with_columns_on_demand(attr_name, *args)
      if columns_to_load_on_demand.include?(attr_name)
        load_attributes(attr_name)
      else
        missing_attribute_without_columns_on_demand(attr_name, *args)
      end
    end
    
    def reload_with_columns_on_demand(*args)
      reload_without_columns_on_demand(*args).tap do
        columns_to_load_on_demand.each {|attr_name| @attributes.delete(attr_name)}
      end
    end
  end
end
