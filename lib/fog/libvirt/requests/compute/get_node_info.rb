module Fog
  module Libvirt
    class Compute
      module Shared
        def get_node_info
          node_hash = Hash.new
          node_info = client.node_get_info
          [:model, :memory, :cpus, :mhz, :nodes, :sockets, :cores, :threads].each do |param|
            node_hash[param] = node_info.send(param) rescue nil
          end
          [:type, :version, :node_free_memory, :max_vcpus].each do |param|
            node_hash[param] = client.send(param) rescue nil
          end
          node_hash[:uri] = client.uri
          if (xml = sys_info)
            [:uuid, :manufacturer, :product, :serial].each do |attr|
              element = xml / "sysinfo/system/entry[@name=#{attr}]"
              node_hash[attr] = element&.text&.strip
            end
          end

          node_hash[:hostname] = client.hostname
          [node_hash]
        end

        private

        def sys_info
          Nokogiri::XML(client.sys_info)
        rescue LibvirtError
          # qemu:///session typically doesn't have permission to retrieve this
        rescue StandardError
          # TODO: log this?
        end
      end

      class Real
        include Shared
      end

      class Mock
        include Shared
      end
    end
  end
end
