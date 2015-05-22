#!/usr/local/bin/ruby
# encoding: utf-8

Encoding.default_external = Encoding::UTF_8
$stdout.sync = true

# TODO: Check if docker socket is mounted

# TODO: Check if ETCD is set up

Dir.glob('/mech/managers/*.rb') { |file| require file }
