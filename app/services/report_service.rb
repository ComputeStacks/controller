##
# Reporting Service
#
# Temporary helper service to perform basic data exports.
#
# Returns RAW csv data. Does not create file.
#
# To create a file, use:
#     File.open('/usr/src/app/tmp/data.csv', 'w') { |f| f.write(data) }
#
class ReportService

  attr_accessor :klass

  def initialize(klass)
    self.klass = klass.to_s
  end

  def perform
    case klass
    when 'Deployment::Container'
      container_export
    else
      nil
    end
  end

  private

  def container_export
    CSV.generate(headers: true) do |csv|
      csv << %w(id project user package image region node created)
      Deployment::Container.all.each do |i|
        package = i.service.package
        plan = package.nil? ? '' : package.product.name
        csv << [i.id, i.deployment.name, i.user&.email, plan, i.container_image.label, i.region.name, i.node.label, i.created_at.iso8601]
      end
    end
  end


end
