require 'test_helper'

class Network::CidrTest < ActiveSupport::TestCase

  test 'can generate new ip address' do
    VCR.use_cassette('network_cidr_generate_ip') do
      1.upto(5) do
        network = Network.first
        new_cidr = Network::Cidr.new(network: network)
        assert new_cidr.save
        assert_not_nil new_cidr.cidr
      end
    end
  end

end
