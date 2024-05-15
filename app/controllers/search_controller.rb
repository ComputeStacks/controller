class SearchController < AuthController

  def new; end

  def create
    sparams = {
      deployments: [],
      cidr: [],
      containers: [],
      container_services: [],
      volumes: [],
      container_domains: [],
      dns_zones: [],
      images: []
    }
    unless params[:q].nil? || params[:q] == ""
      @q = params[:q].downcase.allowed_query
      uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
      if uuid_regex.match?(@q)
        sparams[:volumes] = Volume.find_all_for(current_user).where(name: @q)
        sparams[:deployments] = Deployment.find_all_for(current_user).where(token: @q)
      elsif @q =~ Resolv::IPv4::Regex # IP Address
        sparams[:cidr] = Network::Cidr.where(cidr: @q)
      else
        sparams[:deployments] = Deployment.find_all_for(current_user).where Arel.sql %Q(lower(deployments.name) ~ '#{@q}')
        sparams[:containers] = Deployment::Container.find_all_for(current_user).where Arel.sql %Q(lower(deployment_containers.name) ~ '#{@q}')
        sparams[:container_services] = Deployment::ContainerService.find_all_for(current_user).where Arel.sql %Q( lower(deployment_container_services.name) ~ '#{@q}' OR lower(deployment_container_services.label) ~ '#{@q}' )
        sparams[:volumes] = Volume.find_all_for(current_user).where Arel.sql %Q( lower(volumes.name) ~ '#{@q}' OR lower(volumes.label) ~ '#{@q}' )
        sparams[:container_domains] = Deployment::ContainerDomain.find_all_for(current_user).where Arel.sql %Q(domain ~ '#{@q}')
        sparams[:dns_zones] = Dns::Zone.find_all_for(current_user).where Arel.sql %Q( dns_zones.name ~ '#{@q}' )
        sparams[:images] = ContainerImage.find_all_for(current_user).where Arel.sql %Q(lower(container_images.name) ~ '#{@q}' OR lower(container_images.label) ~ '#{@q}')
      end
    end
    @search_params = []
    sparams[:cidr].each do |i|
      next if i.container.nil?
      next unless i.container.can_view?(current_user)
      @search_params << {
        label: "<span class='label label-info'>Container</span>",
        link: "/containers/#{i.container.id}",
        title: "#{i.ipaddr} (#{i.container.name})",
        created_at: i.created_at
      }
    end
    sparams[:deployments].each do |i|
      @search_params << {
        label: "<span class='label label-primary'>Project</span>",
        link: "/deployments/#{i.token}",
        title: i.name,
        created_at: i.created_at
      }
    end
    sparams[:containers].each do |i|
      @search_params << {
        label: "<span class='label label-info'>Container</span>",
        link: "/containers/#{i.id}",
        title: i.name,
        created_at: i.created_at
      }
    end
    sparams[:container_services].each do |i|
      @search_params << {
        label: "<span class='label label-danger'>ContainerService</span>",
        link: "/container_services/#{i.id}",
        title: i.label,
        created_at: i.created_at
      }
    end
    sparams[:volumes].each do |i|
      @search_params << {
        label: "<span class='label label-danger'>Volume</span>",
        link: "/volumes/#{i.id}",
        title: "Volume #{i.id} (#{i.label})",
        created_at: i.created_at
      }
    end
    sparams[:container_domains].each do |i|
      @search_params << {
        label: "<span class='label label-info'>Domain</span>",
        link: "/container_domains/#{i.id}",
        title: i.container_service ? "#{i.domain} (#{i.container_service.label})" : i.domain,
        created_at: i.created_at
      }
    end
    sparams[:dns_zones].each do |i|
      @search_params << {
        label: "<span class='label label-warning'>DNS Zone</span>",
        link: "/dns/#{i.id}",
        title: i.name,
        created_at: i.created_at
      }
    end
    sparams[:images].each do |i|
      @search_params << {
        label: %q(<span class="label label-warning">Image</span>),
        link: "/container_images/#{i.id}",
        title: i.label,
        created_at: i.created_at
      }
    end
  end

end
