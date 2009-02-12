require 'columns_on_demand'
ActiveRecord::Base.send(:extend, ColumnsOnDemand::BaseMethods)
