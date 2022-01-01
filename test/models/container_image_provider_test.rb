require 'test_helper'

class ContainerImageProviderTest < ActiveSupport::TestCase
  
  test 'can create provider' do
    @provider = ContainerImageProvider.new(
      name: "My Test Repo",
      is_default: false,
      hostname: "myrepo.net"
    )
    assert @provider.valid?
  end

end
