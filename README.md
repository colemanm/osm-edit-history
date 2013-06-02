# OSM Edit History Importer

This is a command line tool for importing changeset data and edit history from [OsmChange](http://wiki.openstreetmap.org/wiki/OsmChange) documents. Changeset files downloaded from the [Changesets API](http://wiki.openstreetmap.org/wiki/API_v0.6#Changesets_2)[^terms] can be parsed and imported into a Postgres database for searching, manipulating, and visualizing.

This was built primarily for analyzing editing history from [Pushpin](http://pushpinosm.org/), but could be useful for other purposes.

## Requirements

* Postgres 9.x
* Ruby 1.9
* Bundler
* A batch of OSM changeset XML files

## Setup

This tool relies on having a connection settings file pre-populated with the Postgres connection parameters, so copy over the sample to your home directory and modify the settings accordingly. You can add new connections by name (just copy the localhost example), then pass the connection name as an argument to run your import against a different database.

    $ cp utils/postgres.sample.yml ~/.postgres

Install the dependencies:

    $ bundle

First, create a database to house your data:

    $ createdb osmedits

Then run the setup task to create the proper tables:

    $ ./osm_edit_history.rb setup -c localhost -d osmedits

## Import

Once you're all set up, run the import task and pass it your Postgres connection name, database, and a path to a directory of XML changeset files, and the importer will populate the tables:

    $ ./osm_edit_history.rb import -c localhost -d osmedits -p /path/to/data

The tool creates two tables: `changes` and `tags`. The `tags` table contains a changeset ID for each tag for cross-referencing or joins.

[^terms]: Keep in mind the API [usage policies](http://wiki.openstreetmap.org/wiki/API_usage_policy) for larger downloads.