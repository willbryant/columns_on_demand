module ColumnsOnDemand
  module BaseMethods
    def columns_on_demand(*columns_to_load_on_demand)
      class_attribute :columns_to_load_on_demand, :instance_writer => false
      self.columns_to_load_on_demand = columns_to_load_on_demand.empty? ? blob_and_text_columns : columns_to_load_on_demand.collect(&:to_s)

      extend ClassMethods
      include InstanceMethods

      class <<self
        unless ActiveRecord::VERSION::MAJOR > 3 ||
              (ActiveRecord.const_defined?(:AttributeMethods) &&
               ActiveRecord::AttributeMethods::const_defined?(:Serialization) &&
               ActiveRecord::AttributeMethods::Serialization::const_defined?(:Attribute))
          alias_method_chain :define_read_method_for_serialized_attribute, :columns_on_demand
        end
        alias_method_chain :reset_column_information,        :columns_on_demand
      end
      alias_method_chain   :attributes,                      :columns_on_demand
      alias_method_chain   :attribute_names,                 :columns_on_demand
      alias_method_chain   :read_attribute,                  :columns_on_demand
      alias_method_chain   :read_attribute_before_type_cast, :columns_on_demand
      if ActiveRecord::AttributeMethods::Read.instance_methods.include?(:_read_attribute)
        alias_method_chain :_read_attribute,                 :columns_on_demand
      end
      alias_method_chain   :missing_attribute,               :columns_on_demand
      alias_method_chain   :reload,                          :columns_on_demand
      if ActiveRecord::AttributeMethods::Dirty.instance_methods.include?(:attribute_changed_in_place?)
        alias_method_chain :attribute_changed_in_place?,     :columns_on_demand
      elsif ActiveRecord::AttributeMethods::Dirty.instance_methods.include?(:changed_attributes)
        alias_method_chain :changed_in_place?,               :columns_on_demand
      end
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
      !columns_to_load_on_demand.include?(attr_name) || @attributes.key?(attr_name) || new_record? || columns_loaded.include?(attr_name)
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

      values = self.class.connection.select_rows(
        "SELECT #{attr_names.collect {|attr_name| self.class.connection.quote_column_name(attr_name)}.join(", ")}" +
        "  FROM #{self.class.quoted_table_name}" +
        " WHERE #{self.class.connection.quote_column_name(self.class.primary_key)} = #{self.class.quote_value(id, self.class.columns_hash[self.class.primary_key])}")
      row = values.first || raise(ActiveRecord::RecordNotFound, "Couldn't find #{self.class.name} with ID=#{id}")

      attr_names.each_with_index do |attr_name, i|
        columns_loaded << attr_name
        value = row[i]

        if @attributes.respond_to?(:write_from_database)
          # activerecord 4.2 or later, which make it easy to replicate the normal typecasting and deserialization logic
          @attributes.write_from_database(attr_name, value)

        elsif coder = self.class.serialized_attributes[attr_name]
          # activerecord 4.1 or earlier, with a serialized column
          # for some database adapters, @column_types_override gets populated with type data from query used to load the record originally.
          # this is fine, but unfortunately some special-case "decorate_columns" code in ActiveRecord will wrap those types in serialization
          # objects, and it does this for each column listed in @serialized_column_names *even if they are not present in the query results*.
          # as a result it unfortunately overrides the normal @column_type with a @column_type_override with a nil @column, which explodes
          # when it tries to run the typecast.  make it use the normal @column_type value, since we know that we've loading the regular column.
          @column_types_override.delete(attr_name) if @column_types_override

          if ActiveRecord.const_defined?(:AttributeMethods) &&
             ActiveRecord::AttributeMethods::const_defined?(:Serialization) &&
             ActiveRecord::AttributeMethods::Serialization::const_defined?(:Attribute)
            # in 3.2 @attributes has a special Attribute struct to help cache both serialized and unserialized forms
            @attributes[attr_name] = ActiveRecord::AttributeMethods::Serialization::Attribute.new(coder, value, :serialized)
          elsif ActiveRecord::VERSION::MAJOR == 3 && ActiveRecord::VERSION::MINOR == 1
            # from 3.1 it has the deserialized form
            @attributes[attr_name] = coder.load value
          else
            # in 2.3 an 3.0, @attributes has the serialized form
            @attributes[attr_name] = value
          end
        else
          # activerecord 4.1 or earlier, with a regular unserialized column
          @attributes[attr_name] = value
        end
      end
    end

    def ensure_loaded(attr_name)
      load_attributes(attr_name.to_s) unless column_loaded?(attr_name.to_s)
    end

    def changed_in_place_with_columns_on_demand?(attr_name)
      column_loaded?(attr_name) && changed_in_place_without_columns_on_demand?(attr_name)
    end

    def attribute_changed_in_place_with_columns_on_demand?(attr_name)
      column_loaded?(attr_name) && attribute_changed_in_place_without_columns_on_demand?(attr_name)
    end

    def read_attribute_with_columns_on_demand(attr_name, &block)
      ensure_loaded(attr_name)
      read_attribute_without_columns_on_demand(attr_name, &block)
    end

    def read_attribute_before_type_cast_with_columns_on_demand(attr_name)
      ensure_loaded(attr_name)
      read_attribute_before_type_cast_without_columns_on_demand(attr_name)
    end

    def _read_attribute_with_columns_on_demand(attr_name, &block)
      ensure_loaded(attr_name)
      _read_attribute_without_columns_on_demand(attr_name, &block)
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
        columns_to_load_on_demand.each do |attr_name|
          if @attributes.respond_to?(:reset)
            # 4.2 and above
            @attributes.reset(attr_name)
          else
            # 4.1 and earlier
            @attributes.delete(attr_name)
          end
        end
      end
    end
  end

  module RelationMethodsArity2
    def build_select_with_columns_on_demand(arel, selects)
      if (selects.empty? || selects == [table[Arel.star]] || selects == ['*']) && klass < ColumnsOnDemand::InstanceMethods
        build_select_without_columns_on_demand(arel, [default_select(true)])
      else
        build_select_without_columns_on_demand(arel, selects)
      end
    end
  end

  module RelationMethodsArity1
    def build_select_with_columns_on_demand(arel)
      if (select_values.empty? || select_values == [table[Arel.star]] || select_values == ['*']) && klass < ColumnsOnDemand::InstanceMethods
        arel.project(*arel_columns([default_select(true)]))
      else
        build_select_without_columns_on_demand(arel)        
      end
    end
  end
end

ActiveRecord::Base.send(:extend, ColumnsOnDemand::BaseMethods)

if ActiveRecord.const_defined?(:Relation)
  if ActiveRecord::Relation.instance_method(:build_select).arity == 1
    # 4.2.1 and above
    ActiveRecord::Relation.send(:include, ColumnsOnDemand::RelationMethodsArity1)
  else
    # 4.2.0 and below
    ActiveRecord::Relation.send(:include, ColumnsOnDemand::RelationMethodsArity2)
  end

  ActiveRecord::Relation.alias_method_chain :build_select, :columns_on_demand
end
