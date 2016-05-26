#!/usr/local/bin/ruby
# encoding: utf-8

Encoding.default_external = Encoding::UTF_8
$stdout.sync = true

# TODO: Check if docker socket is mounted

# TODO: Check if ETCD is set up

# A map of docker Server API versions to client versions
VERSION_MAP = {
	'1.21' => '1.9',
	'1.22' => '1.10'
}

# Swap to the correct docker client
version_error =`docker version 2>&1`.split("\n").last[/Error response from daemon: (client and server don't have same version|client is newer than server).*/]
if version_error
	server_api_version = version_error[/server\sAPI\sversion:\s\d\.\d\d/][/\d\.\d\d/]
	client_version = VERSION_MAP[server_api_version]
	File.delete('/usr/bin/docker')
	File.symlink("/usr/bin/docker#{client_version}", '/usr/bin/docker')
end

Dir.glob('/mech/managers/*.rb') { |file| require file }
