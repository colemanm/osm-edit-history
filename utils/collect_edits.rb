#!/usr/bin/env ruby

# Download edits by changeset ID via the OpenStreetMap API
# Reads from a text file of changeset IDs to download the historical edit data

# Usage:
# ./collect_edits.rb changesets.txt

api_url = "http://api.openstreetmap.org"
changesets = File.read(ARGV[0])

changesets.each_line do |l|
  id = l.chomp
  next if File.exist?("data/xml/#{id}.xml")
  `curl -s --location --globoff '#{api_url}/api/0.6/changeset/#{id}/download' > data/xml/#{id}.xml`
  puts "Downloaded #{id}.xml"
end
