if ActiveRecord::VERSION::MAJOR == 3 && ActiveRecord::VERSION::MINOR < 2
  # this is from 3.1's test suite.  ugly.
  class SQLCounter
    cattr_accessor :ignored_sql
    self.ignored_sql = [/^PRAGMA (?!(table_info))/, /^SELECT currval/, /^SELECT CAST/, /^SELECT @@IDENTITY/, /^SELECT @@ROWCOUNT/, /^SAVEPOINT/, /^ROLLBACK TO SAVEPOINT/, /^RELEASE SAVEPOINT/, /^SHOW max_identifier_length/, /^BEGIN/, /^COMMIT/]

    # FIXME: this needs to be refactored so specific database can add their own
    # ignored SQL.  This ignored SQL is for Oracle.
    ignored_sql.concat [/^select .*nextval/i, /^SAVEPOINT/, /^ROLLBACK TO/, /^\s*select .* from all_triggers/im]

    def self.clear_log
      $queries_executed = []
    end

    def initialize
      $queries_executed.clear
    end

    def call(name, start, finish, message_id, values)
      sql = values[:sql]

      # FIXME: this seems bad. we should probably have a better way to indicate
      # the query was cached
      unless ['CACHE', 'SCHEMA'].include?(values[:name]) # we have altered this from the original, to exclude SCHEMA as well
        # debugger if sql =~ /^PRAGMA table_info/ && Kernel.caller.any? {|i| i.include?('test_it_creates_named_class_methods_if_a_')}
        $queries_executed << sql unless self.class.ignored_sql.any? { |r| sql =~ r }
      end
    end
  end
  ActiveSupport::Notifications.subscribe('sql.active_record', SQLCounter.new)
else
  # this is from 3.2's test suite.  ugly.
  class SQLCounter
    cattr_accessor :ignored_sql
    self.ignored_sql = [/^PRAGMA (?!(table_info))/, /^SELECT currval/, /^SELECT CAST/, /^SELECT @@IDENTITY/, /^SELECT @@ROWCOUNT/, /^SAVEPOINT/, /^ROLLBACK TO SAVEPOINT/, /^RELEASE SAVEPOINT/, /^SHOW max_identifier_length/, /^BEGIN/, /^COMMIT/]

    # FIXME: this needs to be refactored so specific database can add their own
    # ignored SQL.  This ignored SQL is for Oracle.
    ignored_sql.concat [/^select .*nextval/i, /^SAVEPOINT/, /^ROLLBACK TO/, /^\s*select .* from all_triggers/im]

    cattr_accessor :log
    self.log = []

    attr_reader :ignore

    def self.clear_log
      self.log.clear
    end

    def initialize(ignore = self.class.ignored_sql)
      @ignore   = ignore
    end

    def call(name, start, finish, message_id, values)
      sql = values[:sql]

      # FIXME: this seems bad. we should probably have a better way to indicate
      # the query was cached
      return if 'CACHE' == values[:name] || ignore.any? { |x| x =~ sql }
      self.class.log << sql
    end
  end

  ActiveSupport::Notifications.subscribe('sql.active_record', SQLCounter.new)
end
