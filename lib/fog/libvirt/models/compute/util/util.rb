require 'securerandom'

module Fog
  module Libvirt
    module Util
      def randomized_name
        "fog-#{(SecureRandom.random_number*10E14).to_i.round}"
      end
    end
  end
end
