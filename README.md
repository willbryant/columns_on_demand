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

Currently tested against Rails 7.2.0.beta2, 7.1.3.4, 7.0.8.4, and 6.1.7.8, with older gem versions compatible with earlier Rails versions.


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
* Jens Schmidt (@w3dot0)

Copyright (c) 2008-2024 Will Bryant, Sekuda Ltd, released under the MIT license
