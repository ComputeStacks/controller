desc "Install all container images"
task load_containers: :environment do

  Rake.application.in_namespace(:containers) do |i|
    i.tasks.each do |ii|
      ii.invoke
    end
  end

end
