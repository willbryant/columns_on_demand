module ColumnsOnDemand
  module BaseMethods
    def columns_on_demand(*columns_to_load_on_demand)
      class_attribute :columns_to_load_on_demand, :instance_writer => false
      self.columns_to_load_on_demand = columns_to_load_on_demand.empty? ? blob_and_text_columns : columns_to_load_on_demand.collect(&:to_s)

      extend ClassMethods
      prepend InstanceMethods

      class <<self
        alias reset_column_information_without_columns_on_demand reset_column_information
        alias reset_column_information reset_column_information_with_columns_on_demand
      end
    end
    
    def reset_column_information_with_columns_on_demand
      @columns_to_select = @columns_to_load_by_default = nil
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
      @columns_to_select ||= columns_to_load_by_default.collect {|attr_name| connection.quote_column_name(attr_name)}
      if qualified
        quoted_table_name + '.' + @columns_to_select.join(", #{quoted_table_name}.")
      else
        @columns_to_select.join(", ")
      end
    end

    def columns_to_load_by_default
      @columns_to_load_by_default ||= Set.new(columns.collect(&:name) - columns_to_load_on_demand)
    end
  end
  
  module InstanceMethods
    def columns_loaded
      @columns_loaded ||= Set.new
    end

    def column_loaded?(attr_name)
      !columns_to_load_on_demand.include?(attr_name) || @attributes.key?(attr_name) || new_record? || columns_loaded.include?(attr_name)
    end

    def attributes
      loaded_attributes = @attributes.keys
      if loaded_attributes.size == self.class.columns_to_load_by_default.size &&
         loaded_attributes.size == (self.class.columns_to_load_by_default & loaded_attributes).size
        load_attributes(*columns_to_load_on_demand.reject {|attr_name| column_loaded?(attr_name)})
      end
      super
    end

    def attribute_names
      (super + columns_to_load_on_demand).uniq.sort
    end

    def attribute_method?(attr_name)
      super || columns_to_load_on_demand.include?(attr_name)
    end

    def _has_attribute?(attr_name)
      super || columns_to_load_on_demand.include?(attr_name)
    end
    
    def load_attributes(*attr_names)
      return if attr_names.blank?

      values = self.class.connection.select_rows(
        "SELECT #{attr_names.collect {|attr_name| self.class.connection.quote_column_name(attr_name)}.join(", ")}" +
        "  FROM #{self.class.quoted_table_name}" +
        " WHERE #{self.class.connection.quote_column_name(self.class.primary_key)} = #{self.class.connection.quote(id)}")
      row = values.first || raise(ActiveRecord::RecordNotFound, "Couldn't find #{self.class.name} with ID=#{id}")

      attr_names.each_with_index do |attr_name, i|
        columns_loaded << attr_name
        value = row[i]
        @attributes.write_from_database(attr_name, value)
      end
    end

    def ensure_loaded(attr_name)
      load_attributes(attr_name.to_s) unless column_loaded?(attr_name.to_s)
    end

    def changed_in_place?(attr_name)
      column_loaded?(attr_name) && super(attr_name)
    end

    def attribute_changed_in_place?(attr_name)
      column_loaded?(attr_name) && super(attr_name)
    end

    def read_attribute(attr_name, &block)
      ensure_loaded(attr_name)
      super(attr_name, &block)
    end

    def read_attribute_before_type_cast(attr_name)
      ensure_loaded(attr_name)
      super(attr_name)
    end

    def _read_attribute(attr_name, &block)
      ensure_loaded(attr_name)
      super(attr_name, &block)
    end

    def write_attribute(attr_name, value)
      ensure_loaded(attr_name)
      super(attr_name, value)
    end

    def _write_attribute(attr_name, value)
      ensure_loaded(attr_name)
      super(attr_name, value)
    end

    def missing_attribute(attr_name, *args)
      if columns_to_load_on_demand.include?(attr_name)
        load_attributes(attr_name)
      else
        super(attr_name, *args)
      end
    end

    def reload(*args)
      super(*args).tap do
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

  module RelationMethods
    def build_select(arel)
      if (select_values.empty? || select_values == [table[Arel.star]] || select_values == ['*']) && klass < ColumnsOnDemand::InstanceMethods
        arel.project(*arel_columns([default_select(true)]))
      else
        super(arel)
      end
    end
  end
end

ActiveRecord::Base.send(:extend, ColumnsOnDemand::BaseMethods)
ActiveRecord::Relation.send(:prepend, ColumnsOnDemand::RelationMethods)

# work around ActiveRecord 5.0 and 5.1 converting uninitialized attributes to value nil on save
# (due to dirty.rb mapping @attributes).  this is not only a problem for columns_on_demand as it
# means that a MissingAttributeError will never be raised after save, but we suffer more.
# ActiveRecord 4.2's Attribute doesn't have forgetting_assignment (or this problem).
if ActiveRecord.const_defined?(:Attribute) && ActiveRecord::Attribute.uninitialized(nil, nil).try(:forgetting_assignment).try(:initialized?)
  module ActiveRecord
    class Attribute # :nodoc:
      class Uninitialized < Attribute # :nodoc:
        def forgetting_assignment
          dup
        end
      end
    end
  end
end

# same for 5.2
if ActiveModel.const_defined?(:Attribute) && ActiveModel::Attribute.uninitialized(nil, nil).try(:forgetting_assignment).try(:initialized?)
  module ActiveModel
    class Attribute # :nodoc:
      class Uninitialized < Attribute # :nodoc:
        def forgetting_assignment
          dup
        end
      end
    end
  end
end
