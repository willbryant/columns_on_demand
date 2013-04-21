module ColumnsOnDemand
  module BaseMethods
    def columns_on_demand(*columns_to_load_on_demand)
      class_attribute :columns_to_load_on_demand, :instance_writer => false
      self.columns_to_load_on_demand = columns_to_load_on_demand.empty? ? blob_and_text_columns : columns_to_load_on_demand.collect(&:to_s)

      extend ClassMethods
      include InstanceMethods

      class <<self
        unless ActiveRecord.const_defined?(:AttributeMethods) &&
               ActiveRecord::AttributeMethods::const_defined?(:Serialization) &&
               ActiveRecord::AttributeMethods::Serialization::Attribute
          alias_method_chain :define_read_method_for_serialized_attribute, :columns_on_demand
        end
        alias_method_chain :reset_column_information,        :columns_on_demand
      end
      alias_method_chain   :attributes,                      :columns_on_demand
      alias_method_chain   :attribute_names,                 :columns_on_demand
      alias_method_chain   :read_attribute,                  :columns_on_demand
      alias_method_chain   :read_attribute_before_type_cast, :columns_on_demand
      alias_method_chain   :missing_attribute,               :columns_on_demand
      alias_method_chain   :reload,                          :columns_on_demand
    end
    
    def reset_column_information_with_columns_on_demand
      @columns_to_select = nil
      reset_column_information_without_columns_on_demand
    end
    
    def define_read_method_for_serialized_attribute_with_columns_on_demand(attr_name)
      define_read_method_for_serialized_attribute_without_columns_on_demand(attr_name)
      scope = method_defined?(:generated_attribute_methods) ? generated_attribute_methods : self
      scope.module_eval("def #{attr_name}_with_columns_on_demand; ensure_loaded('#{attr_name}'); #{attr_name}_without_columns_on_demand; end; alias_method_chain :#{attr_name}, :columns_on_demand", __FILE__, __LINE__)      
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
    def columns_loaded
      @columns_loaded ||= Set.new
    end

    def column_loaded?(attr_name)
      !columns_to_load_on_demand.include?(attr_name) || !@attributes[attr_name].nil? || new_record? || columns_loaded.include?(attr_name)
    end

    def attributes_with_columns_on_demand
      load_attributes(*columns_to_load_on_demand.reject {|attr_name| column_loaded?(attr_name)})
      attributes_without_columns_on_demand
    end

    def attribute_names_with_columns_on_demand
      (attribute_names_without_columns_on_demand + columns_to_load_on_demand).uniq.sort
    end
    
    def load_attributes(*attr_names)
      return if attr_names.blank?
      values = connection.select_rows(
        "SELECT #{attr_names.collect {|attr_name| connection.quote_column_name(attr_name)}.join(", ")}" +
        "  FROM #{self.class.quoted_table_name}" +
        " WHERE #{connection.quote_column_name(self.class.primary_key)} = #{quote_value(id, self.class.columns_hash[self.class.primary_key])}")
      row = values.first || raise(ActiveRecord::RecordNotFound, "Couldn't find #{self.class.name} with ID=#{id}")
      attr_names.each_with_index do |attr_name, i|
        columns_loaded << attr_name
        @attributes[attr_name] = row[i]

        if coder = self.class.serialized_attributes[attr_name]
          if ActiveRecord.const_defined?(:AttributeMethods) &&
             ActiveRecord::AttributeMethods::const_defined?(:Serialization) &&
             ActiveRecord::AttributeMethods::Serialization::Attribute
            # in 3.2 @attributes has a special Attribute struct to help cache both serialized and unserialized forms
            @attributes[attr_name] = ActiveRecord::AttributeMethods::Serialization::Attribute.new(coder, @attributes[attr_name], :serialized)
          elsif ActiveRecord::VERSION::MAJOR == 3 && ActiveRecord::VERSION::MINOR == 1
            # in 2.3 an 3.0, @attributes has the serialized form; from 3.1 it has the deserialized form
            @attributes[attr_name] = coder.load @attributes[attr_name]
          end
        end
      end
    end
    
    def ensure_loaded(attr_name)
      load_attributes(attr_name.to_s) unless column_loaded?(attr_name.to_s)
    end
    
    def read_attribute_with_columns_on_demand(attr_name)
      ensure_loaded(attr_name)
      read_attribute_without_columns_on_demand(attr_name)
    end

    def read_attribute_before_type_cast_with_columns_on_demand(attr_name)
      ensure_loaded(attr_name)
      read_attribute_before_type_cast_without_columns_on_demand(attr_name)
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
        columns_loaded.clear
        columns_to_load_on_demand.each {|attr_name| @attributes.delete(attr_name)}
      end
    end
  end

  module RelationMethods
    def build_select_with_columns_on_demand(arel, selects)
      if selects.empty? && klass < ColumnsOnDemand::InstanceMethods
        build_select_without_columns_on_demand(arel, default_select(true))
      else
        build_select_without_columns_on_demand(arel, selects)
      end
    end
  end
end

ActiveRecord::Base.send(:extend, ColumnsOnDemand::BaseMethods)
if ActiveRecord.const_defined?(:Relation)
  ActiveRecord::Relation.send(:include, ColumnsOnDemand::RelationMethods)
  ActiveRecord::Relation.alias_method_chain :build_select, :columns_on_demand
end
