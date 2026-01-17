#!/bin/sh

set -e

for version in 6.1.7.8 7.0.10
do
	RAILS_VERSION=$version SQLITE3_VERSION=1.5.0 bundle update rails sqlite3
	RAILS_ENV=sqlite3 bundle exec rake
	RAILS_ENV=postgresql bundle exec rake
	RAILS_ENV=mysql2 bundle exec rake
done

for version in 7.1.6 7.2.3 8.0.4 8.1.2
do
	RAILS_VERSION=$version SQLITE3_VERSION=2.1.0 bundle update rails sqlite3
	RAILS_ENV=sqlite3 bundle exec rake
	RAILS_ENV=postgresql bundle exec rake
	RAILS_ENV=mysql2 bundle exec rake
done
