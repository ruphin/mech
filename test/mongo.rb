require '/mech/lib/main'

$USE_ETCD = true

Mech.manager('mongo') do
  def configure_worker
    return {
      image: 'mongo:3.0',
      volumes: {'/tmp' => '/tmp'},
      env: {'something' => 'true'},
      ports: {200 => 300},
      hostname: 'mongohost'
    }
  end

  def config_changed(change)
    puts change
  end

end