#!/usr/bin/env ruby

require 'rubygems'
require 'thor'
require 'nokogiri'
require 'yaml'
require 'open-uri'
require 'active_support/all'
require 'pg'
require 'sequel'

class OsmEditHistory < Thor
  desc "setup", "Setup a database"
  method_option :connection, aliases: "-c", desc: "Postgres connection name"
  method_option :database, aliases: "-d", desc: "Postgres database"
  def setup
    setup_database
  end

  desc "import", "Import changesets and tags from XML history files"
  method_option :path, aliases: "-p", desc: "Path to directory containing XML changeset files"
  method_option :connection, aliases: "-c", desc: "Postgres connection name"
  method_option :database, aliases: "-d", desc: "Postgres database"
  def import
    Dir.glob("#{options[:path]}/*.xml") do |file|
      xml = File.open(file).read
      change = parse_changesets(xml)
      puts "Reading #{File.basename(file)}..."
      if !changeset_exists(change['changeset_id'])
        insert_changeset(change.except("tags"))
        insert_tags(change)
        puts "Imported edits for changeset #{change['changeset_id']}."
      end
    end
  end

  desc "clean", "Detect and remove empty changeset files"
  method_option :path, aliases: "-p", desc: "Path to directory containing XML changeset files"
  def clean
    Dir.glob("#{options[:path]}/*.xml") do |file|
      xml = File.open(file).read
      if !changeset_valid(xml)
        File.delete(file)
        puts "File #{File.basename(file)} deleted."
      end
    end
  end

  desc "download", "Download changeset files from text list"
  method_option :path, aliases: "-p", desc: "Path to store downloaded XML changeset files"
  method_option :file, aliases: "-f", desc: "Text file of changeset IDs"
  def download
    api_url = "http://api.openstreetmap.org/api/0.6"
    file = File.read(options[:file])
    file.each_line do |l|
      id = l.chomp
      next if File.exist?("#{options[:path]}/#{id}.xml")
      `curl -s --location --globoff '#{api_url}/changeset/#{id}/download' > #{options[:path]}/#{id}.xml`
      puts "Downloaded #{id}.xml"
    end
  end

  no_tasks do
    def database
      settings = YAML.load(File.read(File.expand_path("~/.postgres")))[options[:connection]]
      @db ||= Sequel.connect(adapter: "postgres",
                          host: settings["host"],
                          database: options[:database],
                          user: settings["user"],
                          password: settings["password"])
    end

    def changeset_exists(id)
      database["SELECT COUNT(1) AS count FROM changes WHERE changeset_id = #{id}"].all.first[:count] > 0
    end

    def changeset_valid(xml)
      Nokogiri::XML::Reader(xml).each_with_index do |node, index|
        if node.name == 'osmChange' && node.self_closing?
          return false
        else
          return true
        end
      end
    end

    def insert_changeset(changeset)
      database[:changes].insert(changeset)
    end

    def insert_tags(changeset)
      parse_tags(changeset).each do |tag|
        database[:tags].insert(tag)
      end
    end

    # Parse changeset files in a directory (XML)
    def parse_changesets(xml)
      current_record = nil
      current_type = nil

      Nokogiri::XML::Reader(xml).each_with_index do |node, index|
        if ['create', 'modify'].include? node.name
          current_type = node.name
        end
        if ['node', 'way', 'relation'].include? node.name
          if node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            current_record = node.attributes.merge('tags' => {})
            current_record['osm_id'] = current_record['id'].to_i
            current_record['type'] = node.name
            current_record['edit_type'] = current_type
            current_record['version'] = current_record['version'].to_i
            current_record['changeset_id'] = current_record['changeset'].to_i
            current_record['uid'] = current_record['uid'].to_i
            current_record['created_at'] = Time.parse(current_record['timestamp']) if current_record['timestamp']
            current_record['username'] = current_record.delete('user')
            %w(changeset lat lon visible timestamp id).each { |key| current_record.delete(key) }
          end
        end

        if node.name == 'tag'
          current_record['tags'][node.attributes['k'].gsub('.', '-')] = node.attributes['v']
        end
      end
      return current_record
    end

    # Reformat tags as k=v pairs
    def parse_tags(changeset)
      tags = []
      changeset['tags'].each do |k,v|
        tag = {}
        tag['changeset_id'] = changeset['changeset_id']
        tag['key'] = k
        tag['value'] = v
        tag['edit_type'] = changeset["edit_type"]
        tags << tag
      end
      return tags
    end

    def setup_database
      database.run 'CREATE EXTENSION "hstore"' rescue nil
      database.run create_tables
      database.run create_indexes
    end

    def create_tables
      <<-SQL
        CREATE TABLE changes
        (
          id serial NOT NULL,
          osm_id bigint NOT NULL,
          type character varying(50),
          edit_type character varying(50),
          version integer NOT NULL,
          changeset_id integer NOT NULL,
          username character varying(255),
          uid integer NOT NULL,
          created_at timestamp without time zone,
          CONSTRAINT changes_pkey PRIMARY KEY (id)
        )
        WITH (
          OIDS=FALSE
        );

        CREATE TABLE tags
        (
          id serial NOT NULL,
          changeset_id integer NOT NULL,
          key character varying(255),
          value character varying(255),
          edit_type character varying(50),
          CONSTRAINT tags_pkey PRIMARY KEY (id)
        )
        WITH (
          OIDS=FALSE
        );
SQL
    end

    def create_indexes
      <<-SQL
        CREATE INDEX index_changes_on_osm_id ON changes USING btree (osm_id);
        CREATE INDEX index_changes_on_username ON changes USING btree (username);
        CREATE INDEX index_changes_on_changeset_id ON changes USING btree (changeset_id);
        CREATE INDEX index_changes_on_created_at ON changes USING btree (created_at);
        CREATE INDEX index_tags_on_changeset_id ON tags USING btree (changeset_id);
        CREATE INDEX index_tags_on_key ON tags USING btree (key);
        CREATE INDEX index_tags_on_value ON tags USING btree (value);
  SQL
    end
  end
end

OsmEditHistory.start
