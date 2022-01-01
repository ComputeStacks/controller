module Admin::VolumesHelper

  def volume_subscribers(data)
    result = []
    data[:known].each do |i|
      l = i.is_a?(Deployment::Container) ? container_path(i) : nil
      result << [i.name, {
          container: i,
          node: i.node,
          deployment: i.deployment,
          user: i.user,
          link: l
      }]
    end
    data[:unknown].each do |i|
      result << [i[:container], {
          container: nil,
          node: i[:node],
          deployment: nil,
          user: nil,
          link: nil
      }]
    end
    result.sort
  end

end
