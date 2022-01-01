require 'test_helper'

class Deployment::SftpTest < ActiveSupport::TestCase

  setup do
    @sftp = Deployment::Sftp.first
  end

  test 'can retrieve sftp password' do
    assert_not_nil @sftp.password
  end

  test 'can assign private ip address' do
    assert_not_nil @sftp.local_ip
  end

  test 'has an internal port' do
    refute_nil @sftp.public_port
  end

  test 'can generate docker config' do
    assert_kind_of Hash, @sftp.build_command
  end

end
