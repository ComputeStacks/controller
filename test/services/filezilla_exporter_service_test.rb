require 'test_helper'

class FilezillaExporterServiceTest < ActiveSupport::TestCase

  test 'can generate export for a project' do
    deployment = deployments :project_test
    data = UtilityServices::FilezillaExporterService.new
    data.deployment = deployment
    result = data.perform
    refute_nil result

    parsed_result = Nokogiri::XML result

    assert_kind_of Nokogiri::XML::Document, parsed_result

    ##
    # Basic formatting validation

    # top level
    assert_equal 1, parsed_result.elements.count
    assert_equal "FileZilla3", parsed_result.elements.first.name

    # Server level
    assert_equal 1, parsed_result.elements.first.elements.count
    assert_equal "Servers", parsed_result.elements.first.elements.first.name

    # Folder
    assert_equal Setting.app_name, parsed_result.elements.first.elements.first.children.first.children.first.content

    ##
    # Since we're only using a single deployment, we don't need to worry about looping through 'Folders'.

    # Pick out the project name
    parsed_project_name = parsed_result.elements.first.elements.first.children.first.children.last.children.first.content
    # Grab the individual server elements
    parsed_child_elements = parsed_result.elements.first.elements.first.children.first.children.last.children
    assert_equal deployment.name, parsed_project_name

    # Generate a hash of expected server values to test against
    server = []
    deployment.services.each do |service|

      next unless service.requires_sftp_containers?
      next if service.volumes.sftp_enabled.empty?
      sftp = service.sftp_containers.first
      next if sftp.nil?
      multiple_vols = service.volumes.sftp_enabled.count > 1
      service.volumes.sftp_enabled.each do |vol|
        server << {
          host: sftp.ip_addr,
          port: sftp.public_port.to_s,
          pass: sftp.password,
          name: multiple_vols ? "#{service.label}-#{vol.label}" : service.label,
          remote_dir: "1 0 4 home 8 sftpuser 4 apps #{service.name.length} #{service.name} #{vol.label.length} #{vol.label}"
        }
      end
    end

    refute_empty server

    # Loop over each server hash element
    server.each do |item|
      # Find the correct child by matching the service name
      selected_child = nil
      parsed_child_elements.each do |el|
        next if el.children.empty?
        check_exists = el.children.select {|i| i.name == "Name" && i.content == item[:name]}
        next if check_exists.empty?
        selected_child = el
      end
      # Assert we have a child
      refute_nil selected_child
      selected_child.children.each do |el|
        case el.name
        when "Host"
          assert_equal item[:host], el.content
        when "Port"
          assert_equal item[:port], el.content
        when "Pass"
          assert_equal item[:pass], el.content
        when "Name"
          assert_equal item[:name], el.content
        when "RemoteDir"
          assert_equal item[:remote_dir], el.content
        end
      end
    end


  end

end
