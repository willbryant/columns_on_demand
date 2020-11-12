#!/bin/sh

set -e

for version in 5.0.7.2 5.1.7 5.2.4.4
do
	RAILS_VERSION=$version SQLITE3_VERSION=1.3.9 bundle update rails sqlite3
	RAILS_ENV=sqlite3 bundle exec rake
	RAILS_ENV=postgresql bundle exec rake
	RAILS_ENV=mysql2 bundle exec rake
done

for version in 6.0.3.4
do
	RAILS_VERSION=$version SQLITE3_VERSION=1.4.1 bundle update rails sqlite3
	RAILS_ENV=sqlite3 bundle exec rake
	RAILS_ENV=postgresql bundle exec rake
	RAILS_ENV=mysql2 bundle exec rake
done
