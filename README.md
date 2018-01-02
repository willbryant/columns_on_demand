ColumnsOnDemand
===============

Lazily loads large columns on demand.

By default, does this for all TEXT (:text) and BLOB (:binary) columns, but a list
of specific columns to load on demand can be given.

This is useful to reduce the memory taken by Rails when loading a number of records
that have large columns if those particular columns are actually not required most
of the time.  In this situation it can also greatly reduce the database query time
because loading large BLOB/TEXT columns generally means seeking to other database
pages since they are not stored wholly in the record's page itself.

Although this plugin is mainly used for BLOB and TEXT columns, it will actually
work on all types - and is just as useful for large string fields etc.


Compatibility
=============

Supports mysql, mysql2, postgresql, and sqlite3.

Currently tested against Rails 5.1 (up to 5.1.4), 5.0 (up to 5.0.6), and 4.2 (up to 4.2.10), on Ruby 2.3.4.

For earlier versions of Rails, use an older version of the gem.


Example
=======

`Example.all` will exclude the `file_data` and `processing_log` columns from the
`SELECT` query, and `example.file_data` and `example.processing_log` will load & cache
that individual column value for the record instance:

```ruby
  class Example
    columns_on_demand :file_data, :processing_log
  end
```

Scans the `examples` table columns and registers all TEXT (`:text`) and BLOB (`:binary`) columns for loading on demand:

```ruby
  class Example
    columns_on_demand
  end
```

Thanks
======

* Tim Connor (@tlconnor)
* Tobias Matthies (@tobmatth)
* Phil Ross (@philr)

Copyright (c) 2008-2017 Will Bryant, Sekuda Ltd, released under the MIT license
