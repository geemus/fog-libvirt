Shindo.tests("Fog::Compute[:libvirt] | get_node_info", 'libvirt') do

  compute = Fog::Compute[:libvirt]

  tests("get_node_info response") do
    response = compute.get_node_info
    info = response[0]
    tests("sys_info attributes") do
      [:uuid, :manufacturer, :product, :serial].each do |attr|
        test("attribute #{attr} is set") { info[attr].is_a?(String) }
      end
    end
  end
end
