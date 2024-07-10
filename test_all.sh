#!/bin/sh

set -e

for version in 6.1.7.8 7.0.8.4 7.1.3.4 7.2.0.beta2
do
	RAILS_VERSION=$version SQLITE3_VERSION=1.5.0 bundle update rails sqlite3
	RAILS_ENV=sqlite3 bundle exec rake
	RAILS_ENV=postgresql bundle exec rake
	RAILS_ENV=mysql2 bundle exec rake
done
