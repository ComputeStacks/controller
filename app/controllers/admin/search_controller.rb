class Admin::SearchController < Admin::ApplicationController

  def new
    render template: 'search/new'
  end

  def create
    sparams = {
      users: [],
      deployments: [],
      containers: [],
      cidr: [],
      volumes: [],
      container_domains: [],
      dns_zones: [],
      images: [],
      subscriptions: [],
      product: [],
      sftp: []
    }
    q_filter = nil
    unless params[:q].nil? || params[:q] == ""

      q_filter = if params[:q].split(":").count > 1
                   %w(image user deployment product domain).include?(params[:q].split(":")[0]) ? params[:q].split(":")[0] : nil
                 else
                   nil
                 end
      params[:q] = if q_filter
                     # just strip out the filter rather than selecting from array, in case there are colons elswhere.
                     params[:q].gsub("#{q_filter}:","").strip
                   else
                     params[:q]
                   end

      @q = params[:q].downcase.allowed_query
      uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
      if @q =~ /@/
        sparams[:users] = User.where(Arel.sql(%Q(lower(email) LIKE '%#{@q}%')))
      elsif uuid_regex.match?(@q)
        sparams[:volumes] = Volume.where(name: @q)
        sparams[:deployments] = Deployment.where(token: @q)
      elsif @q.split('.').count == 4 # IP!
        sparams[:cidr] = Network::Cidr.where(cidr: @q) + Node.where( Arel.sql(%Q(primary_ip = '#{@q}' OR public_ip = '#{@q}')) )
      elsif q_filter == 'user'
        sparams[:users] = User.search_by @q
      elsif q_filter == 'image'
        sparams[:images] = ContainerImage.where Arel.sql %Q(lower(name) ~ '#{@q}' OR lower(label) ~ '#{@q}')
      elsif q_filter == 'deployment'
        sparams[:deployments] = Deployment.where(Arel.sql(%Q(lower(name) ~ '#{@q}' OR token LIKE '%#{@q}%')))
      elsif q_filter == 'product'
        sparams[:product] = Product.where Arel.sql %Q(lower(name) ~ '#{@q}' OR lower(label) ~ '#{@q}')
      elsif q_filter == 'domain'
        sparams[:container_domains] = Deployment::ContainerDomain.where( Arel.sql( %Q(domain ~ '#{@q}') ) )
      else
        sparams[:users] = User.search_by @q
        sparams[:deployments] = Deployment.where(Arel.sql(%Q(lower(name) ~ '#{@q}')))
        sparams[:containers] = Deployment::Container.where(Arel.sql(%Q(lower(name) ~ '#{@q}')))
        sparams[:volumes] = Volume.where( Arel.sql( %Q( lower(name) ~ '#{@q}' OR lower(label) ~ '#{@q}' ) ) )
        sparams[:container_domains] = Deployment::ContainerDomain.where( Arel.sql( %Q(domain ~ '#{@q}') ) )
        sparams[:dns_zones] = ::Dns::Zone.where( Arel.sql( %Q( name ~ '#{@q}' ) ) )
        sparams[:images] = ContainerImage.where Arel.sql %Q(lower(name) ~ '#{@q}' OR lower(label) ~ '#{@q}')
        sparams[:subscriptions] = Subscription.where Arel.sql %Q(lower(label) ~ '#{@q}')
        sparams[:product] = Product.where Arel.sql %Q(lower(name) ~ '#{@q}' OR lower(label) ~ '#{@q}')
        sparams[:sftp] = Deployment::Sftp.where(Arel.sql(%Q(lower(name) ~ '#{@q}')))
      end
    end
    @empty_results = true
    sparams.each_key do |k|
      @empty_results = false unless sparams[k].empty?
    end
    @search_params = []
    sparams[:cidr].each do |i|
      if i.is_a?(Network::Cidr)
        t = if i.container.nil?
              i.ipaddr
            else
              "#{i.ipaddr} | #{i.container.name} (#{i.container.node.label})"
            end
        @search_params << {
          label: "<span class='label label-info'>Container</span>",
          link: i.container.nil? ? "/admin/dashboard" : "/admin/containers/#{i.container.id}",
          title: t,
          created_at: i.created_at
        }
      elsif i.is_a?(Node)
        @search_params << {
          label: "<span class='label label-warning'>Node</span>",
          link: "/admin/regions/#{i.region.id}",
          title: i.label,
          created_at: i.created_at
        }
      end
    end
    sparams[:users].each do |i|
      @search_params << {
        label: "<span class='label label-primary'>User</span>",
        link: "/admin/users/#{i.id}-#{i.full_name}",
        title: "#{i.full_name} (#{i.email})",
        created_at: i.created_at
      }
    end
    sparams[:deployments].each do |i|
      @search_params << {
        label: "<span class='label label-warning'>Project</span>",
        link: "/admin/deployments/#{i.id}",
        title: i.name,
        created_at: i.created_at
      }
    end
    sparams[:containers].each do |i|
      @search_params << {
        label: "<span class='label label-info'>Container</span>",
        link: "/admin/containers/#{i.id}",
        title: i.name,
        created_at: i.created_at
      }
    end
    sparams[:volumes].each do |i|
      @search_params << {
        label: "<span class='label label-danger'>Volume</span>",
        link: "/admin/volumes/#{i.id}",
        title: "Volume #{i.id} (#{i.label})",
        created_at: i.created_at
      }
    end
    sparams[:container_domains].each do |i|
      @search_params << {
          label: "<span class='label label-info'>Domain</span>",
          link: "/admin/container_domains/#{i.id}",
          title: i.container_service ? "#{i.domain} (#{i.container_service.label})" : i.domain,
          created_at: i.created_at
      }
    end
    sparams[:dns_zones].each do |i|
      @search_params << {
          label: "<span class='label label-warning'>DNS Zone</span>",
          link: "/admin/dns/#{i.id}",
          title: i.name,
          created_at: i.created_at
      }
    end
    sparams[:images].each do |i|
      t = if i.user
            %Q(#{i.label} (<i class="fa fa-user"></i> #{i.user.full_name}))
          else
            i.label
          end
      @search_params << {
        label: %q(<span class="label label-warning">Image</span>),
        link: "/admin/container_images/#{i.id}",
        title: t,
        created_at: i.created_at
      }
    end
    sparams[:subscriptions].each do |i|
      t = if i.user
            %Q(#{i.label} (<i class="fa fa-user"></i> #{i.user.full_name}))
          else
            i.label
          end
      @search_params << {
        label: %q(<span class="label label-warning">Subscription</span>),
        link: "/admin/subscriptions/#{i.id}",
        title: t,
        created_at: i.created_at
      }
    end
    sparams[:product].each do |i|
      @search_params << {
        label: "<span class='label label-success'>Product</span>",
        link: "/admin/products/#{i.id}",
        title: i.label,
        created_at: i.created_at
      }
    end
    sparams[:sftp].each do |i|
      @search_params << {
        label: "<span class='label label-info'>SFTP</span>",
        link: "/admin/sftp/#{i.id}",
        title: i.name,
        created_at: i.created_at
      }
    end
    # add back in the selector, if present
    @q = "#{q_filter}: #{@q}" if q_filter
    render template: 'search/create'
  end

end
