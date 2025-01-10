RealFile = File
class FakeFile < RealFile
  def self.file?(path)
    path == '/etc/foreman/ceph.conf' || RealFile.file(path)
  end

  def self.readlines(path)
    if path == '/etc/foreman/ceph.conf'
      return [
        "monitor=mon001.example.com,mon002.example.com,mon003.example.com",
        "port=6789",
        "libvirt_ceph_pools=rbd_pool_name,second_rbd_pool_name",
        "auth_username=libvirt",
        "auth_uuid=uuid_of_libvirt_secret",
        "bus_type=virtio"
      ]
    else
      return RealFile.readlines(path)
    end
  end
end

Shindo.tests('Fog::Compute[:libvirt] | server model', ['libvirt']) do

  servers = Fog::Compute[:libvirt].servers
  # Match the mac in dhcp_leases mock
  nics = Fog.mock? ? [{ :type => 'network', :network => 'default', :mac => 'aa:bb:cc:dd:ee:ff' }] : nil
  server = servers.create(:name => Fog::Mock.random_letters(8), :nics => nics)

  before do
    Object.class_eval do
      remove_const(:File)
      const_set(:File, FakeFile)
    end
  end

  after do
    Object.class_eval do
      remove_const(:File)
      const_set(:File, RealFile)
    end
  end

  tests('The server model should') do
    tests('have the action') do
      test('autostart') { server.respond_to? 'autostart' }
      test('update_autostart') { server.respond_to? 'update_autostart' }
      test('reload') { server.respond_to? 'reload' }
      %w{ start stop destroy reboot suspend }.each do |action|
        test(action) { server.respond_to? action }
      end
      %w{ start reboot suspend stop }.each do |action|
        test("#{action} returns successfully") {
          begin
            server.send(action.to_sym)
          rescue Libvirt::Error
            #libvirt error is acceptable for the above actions.
            true
          end
        }
      end
    end
    tests('have an ip_address action that') do
      test('returns the latest IP address lease') { server.public_ip_address() == '1.2.5.6' }
    end
    tests('have attributes') do
      model_attribute_hash = server.attributes
      attributes = [ :id,
        :cpus,
        :cputime,
        :firmware,
        :firmware_features,
        :secure_boot,
        :loader_attributes,
        :os_type,
        :memory_size,
        :max_memory_size,
        :name,
        :arch,
        :persistent,
        :domain_type,
        :uuid,
        :autostart,
        :display,
        :nics,
        :volumes,
        :active,
        :boot_order,
        :hugepages,
        :state]
      tests("The server model should respond to") do
        attributes.each do |attribute|
          test("#{attribute}") { server.respond_to? attribute }
        end
      end
      tests("The attributes hash should have key") do
        attributes.delete(:volumes)
        attributes.each do |attribute|
          test("#{attribute}") { model_attribute_hash.key? attribute }
        end
      end
    end

    test('can destroy') do
      servers.create(:name => Fog::Mock.random_letters(8)).destroy
    end

    test('be a kind of Fog::Libvirt::Compute::Server') { server.kind_of? Fog::Libvirt::Compute::Server }
    tests("serializes to xml") do
      test("without firmware") { server.to_xml.include?("<os>") }
      test("with memory") { server.to_xml.match?(%r{<memory>\d+</memory>}) }
      test("with disk of type file") do
        xml = server.to_xml
        xml.match?(/<disk type="file" device="disk">/) && xml.match?(%r{<source file="#{server.volumes.first.path}"/>})
      end
      test("with disk of type block") do
        server = Fog::Libvirt::Compute::Server.new(
          {
            :nics => [],
            :volumes => [
              Fog::Libvirt::Compute::Volume.new({ :path => "/dev/sda", :pool_name => "dummy" })
            ]
          }
        )
        xml = server.to_xml
        xml.match?(/<disk type="block" device="disk">/) && xml.match?(%r{<source dev="/dev/sda"/>})
      end
      test("with disk of type ceph") do
        server = Fog::Libvirt::Compute::Server.new(
          {
            :nics => [],
            :volumes => [
              Fog::Libvirt::Compute::Volume.new({ :path => "rbd_pool_name/block-1", :pool_name => "rbd_pool_name" }),
              Fog::Libvirt::Compute::Volume.new({ :path => "rbd_pool_name/block-2", :pool_name => "rbd_pool_name" })
            ]
          }
        )
        
        xml = server.to_xml

        network_disk = xml.match?(/<disk type="network" device="disk">/)
        mon_host = xml.match?(%r{<host name="mon001.example.com" port="6789"/>})
        source_block1_rbd = xml.match?(%r{<source protocol="rbd" name="rbd_pool_name/block-1">})
        source_block2_rbd = xml.match?(%r{<source protocol="rbd" name="rbd_pool_name/block-2">})
        auth_username = xml.match?(/<auth username="libvirt">/)
        auth_secret = xml.match?(%r{<secret type="ceph" uuid="uuid_of_libvirt_secret"/>})

        network_disk && mon_host && source_block1_rbd && source_block2_rbd && auth_username && auth_secret
      end
      test("with q35 machine type on x86_64") { server.to_xml.match?(%r{<type arch="x86_64" machine="q35">hvm</type>}) }
    end
    test("with efi firmware") do
      server = Fog::Libvirt::Compute::Server.new(
        {
          :firmware => "efi",
          :nics => [],
          :volumes => []
        }
      )
      xml = server.to_xml

      os_firmware = xml.include?('<os firmware="efi">')
      secure_boot = xml.include?('<feature name="secure-boot" enabled="no"/>')
      loader_attributes = !xml.include?('<loader secure="yes"/>')

      os_firmware && secure_boot && loader_attributes
    end
    test("with secure boot enabled") do
      server = Fog::Libvirt::Compute::Server.new(
        {
          :firmware => "efi",
          :firmware_features => {
            "secure-boot" => "yes",
            "enrolled-keys" => "yes"
          },
          :loader_attributes => { "secure" => "yes" },
          :nics => [],
          :volumes => []
        }
      )
      xml = server.to_xml

      os_firmware = xml.include?('<os firmware="efi">')
      secure_boot = xml.include?('<feature name="secure-boot" enabled="yes"/>')
      enrolled_keys = xml.include?('<feature name="enrolled-keys" enabled="yes"/>')
      loader_attributes = xml.include?('<loader secure="yes"/>')

      os_firmware && secure_boot && enrolled_keys && loader_attributes
    end
  end
end
