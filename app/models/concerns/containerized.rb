##
# =Containerized Models
#
module Containerized
  extend ActiveSupport::Concern

  class_methods do

    # Given a container name, find the local resource
    def resource_by_name(name)
      return nil if name.blank?

      c = Deployment::Container.find_by(name: name)
      c = Deployment::Sftp.find_by(name: name) if c.nil?
      c = LoadBalancer.find_by(name: name) if c.nil?
      c
    end

  end

  # @return [Boolean]
  def latest_image?
    c = docker_client
    # if the container is not on the node, then we _will_ have the latest image
    return true if c.nil?

    c_image_tag = c.info['Config']['Image']
    c_image_id = c.info['Image']

    running_image = Docker::Image.get(c_image_id, {}, node.client(3))

    running_image.info['RepoTags'].include? c_image_tag

  rescue Docker::Error::NotFoundError
    true
  rescue => e
    event.event_details.create!(
      data: e.message,
      event_code: "20fb4e443fde83de"
    )
    false
  end

  def halt_auto_recovery?
    error_events = event_logs.where( Arel.sql(%Q(created_at >= '#{1.hour.ago.iso8601}')) ).starting.failed.count
    start_events = event_logs.where( Arel.sql(%Q(created_at >= '#{30.minutes.ago.iso8601}')) ).starting.count
    stop_events = event_logs.where( Arel.sql(%Q(created_at >= '#{30.minutes.ago.iso8601}')) ).starting.count
    error_events > 3 || start_events > 6 || stop_events > 6
  end

  # Given a raw status from Docker, do we need to intervene?
  # @param [String] docker_status
  # @return [Boolean]
  def requires_intervention?(docker_status)
    return true if docker_status == 'running' && !active?

    %w[created stopped exited].include?(docker_status) && active?
  end

  def metadata_env_params
    [
      %W[METADATA_SERVICE http://metadata.internal:8500/v1/kv/projects/#{deployment.token}],
      %W[METADATA_URL http://metadata.internal:8500/v1/kv/projects/#{deployment.token}/metadata?raw=true],
      %W[METADATA_AUTH #{deployment.consul_auth_key}]
    ]
  end

  # This is used by both Container and SFTP.
  def build!(event)
    build_client = if self.kind_of? Deployment::Container
                     runtime_config event&.audit
                   elsif self.kind_of? Deployment::Sftp
                     build_command
                   else
                     nil
                   end
    return false if build_client.nil?

    Docker::Container.create(build_client, node.client).is_a? Docker::Container
  rescue Docker::Error::ConflictError => e
    event.event_details.create!(
      data: e.message,
      event_code: "f6e058590c10e99e"
    )
    false
  end

  # @param [EventLog] event
  def can_build?(event)
    if built?
      event.event_details.create!(
        data: 'Unable to provision, container is already built; attempting start.',
        event_code: '7ebfd45eba7e7dc8'
      )
      ContainerWorkers::StartWorker.perform_async global_id, event.global_id
      return false
    end
    if node.nil?
      event.event_details.create!(
        data: "Container has no node",
        event_code: 'bf1c1f517b6acefa'
      )
      event.fail! 'Container has no node'
      return false
    end
    unless node.online?
      event.event_details.create!(
        data: 'Node is offline',
        event_code: '4bea557d3255b1af'
      )
      event.fail! 'Node is offline'
      return false
    end
    true
  end

  # @param [Boolean] fast_client
  # @return [Docker::Container,nil]
  def docker_client(fast_client = false)
    Docker::Container.get(self.name, {}, (fast_client ? node.fast_client : node.client(3)))
  rescue Excon::Error::Certificate => e
    # Unable to connect due to invalid certificateX
    ec = '12b4317e8dde17af'
    se = SystemEvent.find_by(event_code: ec)
    if se.nil?
      se = SystemEvent.create!(
        message: "Docker Connection Error: #{node&.region&.name}",
        log_level: 'warn',
        data: { message: nil, count: 0 },
        event_code: ec
      )
    end
    data = se.data
    data[:message] = e.message
    data[:count] = data[:count] + 1
    se.update_attribute :data, data
    nil
  rescue Excon::Error::Socket => e
    # Unable to connect due to _missing_ tls certs on docker
    ec = '06daa76c88d5f72a'
    se = SystemEvent.find_by(event_code: ec)
    if se.nil?
      se = SystemEvent.create!(
        message: "Missing Docker TLS Cert on Node: #{node&.region&.name}",
        log_level: 'warn',
        data: { message: nil, count: 0 },
        event_code: ec
      )
    end
    data = se.data
    data[:message] = e.message
    data[:count] = data[:count] + 1
    se.update_attribute :data, data
    nil
  rescue
    nil
  end

  # @param [Array] command
  # @param [EventLog,nil] event
  def container_exec!(command, event, timeout = 10)
    result = []
    client = docker_client
    return { response: [], exit_code: 2 } if client.nil?

    response = client.exec(command, wait: timeout)
    exit_code = 0
    result << response[0]
    result << response[1] unless response[1].empty?
    exit_code = response[2] if response[2] > exit_code
    if result.count == 1
      result = result[0]
      if result.is_a?(Array)
        d = []
        result.each do |ii|
          d << if ii.kind_of?(Array)
                 ii.join(" ")
               else
                 ii
               end
        end
        result = d.join(" ")
      end
    end
    if event
      event.event_details.create!(
        event_code: '76ed2ba5c0ef8883',
        data: "Exit Code: #{exit_code}\n\nResponse: #{result}"
      )
    end
    {
      response: result,
      exit_code: exit_code
    }
  end

  ##
  # =Load Available Volumes
  #
  # Response
  #     volumes = [{
  #       'service' => service name,
  #       'volume' => Integer,
  #       'label' => String
  #       }]
  # def volumes
  #   Volume.find_by_node(self.node, self.deployment, self.class == Deployment::Sftp)
  # end

  # Real time lookup attached volumes
  #
  # Response
  #     volumes = [{
  #       'service' => service name,
  #       'volume' => Integer,
  #       'label' => String
  #       }]
  def attached_volumes
    result = []
    vol_ids = []
    c = docker_client
    binds = c.info.dig('HostConfig', 'Binds')
    binds = [] if binds.nil?
    binds.each do |m|
      id = m.split(":").first.strip
      vol_ids << id unless vol_ids.include?(id)
    end
    if c.info['Volumes']
      vols = c.info['Volumes']
      vols.each_with_index do |(k, v), i|
        id = Volume.name_by_path(v)
        vol_ids << id if id && !vol_ids.include?(id)
      end
    end
    vol_ids.each do |i|
      vol = Volume.find_by(name: i)
      if vol
        result << {
          'service' => vol.container_service&.name,
          'volume' => vol.name,
          'label' => vol.label.blank? ? vol.container_service.label : vol.label
        }
      end
    end
    result
  rescue
    []
  end

  def can_power?
    !%w[removing rebuilding building migrating].include?(status)
  end

  ##
  # Container Status
  # low-level api to grab raw container state
  #
  # running,stopped,error,degraded
  #
  # degraded = running but healthcheck failed
  ##
  # @return [Hash,nil] { state: state, health: { state: string, count: int, log: [] } }
  def container_status(raw = {})
    return nil if %w[building migrating pending rebuilding trashed].include? status

    if raw.empty?
      if node.nil?
        update status: 'pending'
        nil
      end
      return nil unless node.online?
    elsif raw['State'].nil?
      return nil
    end
    state_raw = raw.empty? ? docker_client(true).info['State'] : raw
    state = (state_raw['Running'] || state_raw['Restarting']) ? 'running' : 'stopped'
    state = 'error' if state == 'stopped' && !state_raw['ExitCode'].zero?
    if state_raw['Health'].nil?
      update status: state
      return { state: state, health: {} }
    end
    if state == 'running'
      state = 'degraded' if state_raw['Health']['Status'] == 'unhealthy'
    end
    update status: state
    { state: state, health: { state: state_raw['Health']['Status'], count: state_raw['Health']['FailingStreak'], log: state_raw['Health']['Log'] }}
  rescue
    nil
  end

  ##
  # Generate the Docker LogDriver config hash
  # @return [Hash]
  def log_driver_config
    ##
    # Temporarily find `loki` to ensure it exists on customer deployments!
    f = Feature.find_by(name: 'loki')
    f = Feature.create!(name: 'loki', maintenance: false, active: true) if f.nil?
    ff = Feature.find_by(name: 'loki_fluentd')
    ff = Feature.create!(name: 'loki_fluentd', maintenance: false, active: false) if ff.nil?
    if f.active
      loki_labels = ['container_name={{.Name}}']
      loki_labels << "project_id=#{deployment.id}" if deployment
      loki_labels << "service_id=#{service.id}" if kind_of?(Deployment::Container)
      if ff.active # Fluentd
        {
          'Type' => 'fluentd',
          'Config' => {
            'fluentd-address' => 'tcp://localhost:9432',
            'labels' => "com.computestacks.deployment_id,com.computestacks.service_id"
          }
        }
      else
        {
          'Type' => 'loki',
          'Config' => {
            'max-size' => '5m',
            'max-file' => '2',
            'loki-url' => "#{region.loki_container_endpoint}/loki/api/v1/push",
            'loki-retries' => region.loki_retries,
            'loki-batch-size' => region.loki_batch_size,
            'loki-external-labels' => "#{loki_labels.join(',')}"
          }
        }
      end
    else
      {
        'Type' => 'json-file',
        'Config' => {
          'max-size' => '5m',
          'max-file' => '2'
        }
      }
    end
  end

end
