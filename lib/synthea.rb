# OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE
# Above line is a temporary certificate solution to upload fhir records to synthetic mass. Uncomment when uploading.
# Top level include file that brings in all the necessary code
require 'bundler/setup'
require 'rubygems'
require 'yaml'
require 'faker'
require 'area'
require 'pickup'
require 'recursive-open-struct'
require 'fhir_models'
require 'fhir_dstu2_models'
require 'fhir_client'
require 'pry'
require 'georuby'
require 'geo_ruby/geojson'
require 'net/sftp'
require 'highline/import'
require 'json'
require 'concurrent'
require 'chunky_png'
require 'graphviz'
require 'distribution'
require 'byebug'

root = File.expand_path '..', File.dirname(File.absolute_path(__FILE__))

module Synthea
end

Synthea::Config = RecursiveOpenStruct.new(YAML.load(ERB.new(File.read(File.join(root, 'config', 'synthea.yml'))).result)['synthea'])
begin
  require 'health-data-standards'
rescue LoadError
  puts '`health-data-standards` failed to load: C-CDA export disabled.'
  Synthea::Config.exporter.ccda.export = false
  Synthea::Config.exporter.html.export = false
end

Dir.glob(File.join(root, 'lib', 'ext', '**', '*.rb')).each do |file|
  require file
end

Dir.glob(File.join(root, 'lib', 'events', '*.rb')).each do |file|
  require file
end
Dir.glob(File.join(root, 'lib', 'events', '**', '*.rb')).each do |file|
  require file
end

require File.join(root, 'lib', 'entity', 'entity.rb')
Dir.glob(File.join(root, 'lib', 'entity', '**', '*.rb')).each do |file|
  require file
end

require File.join(root, 'lib', 'generic', 'metadata.rb')
require File.join(root, 'lib', 'generic', 'hashable.rb')
Dir.glob(File.join(root, 'lib', 'generic', '**', '*.rb')).each do |file|
  require file
end

require File.join(root, 'lib', 'modules', 'module.rb')
Dir.glob(File.join(root, 'lib', 'modules', '*.rb')).each do |file|
  require file
end

Dir.glob(File.join(root, 'lib', 'records', '*.rb')).each do |file|
  require file
end

require File.join(root, 'lib', 'world', 'MA_geo.rb')
Dir.glob(File.join(root, 'lib', 'world', '**', '*.rb')).each do |file|
  require file
end

Dir.glob(File.join(root, 'lib', 'tasks', '**', '*.rb')).each do |file|
  require file
end

Dir.glob(File.join(root, 'lib', 'utils', '**', '*.rb')).each do |file|
  require file
end
