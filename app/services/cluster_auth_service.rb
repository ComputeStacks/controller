# Provide JWT for cluster children to authenticate with the metadata service.
#
# Also used by nodes and load balancers to download their configuration
#
#
# Payload
#    {
#      node_id: Integer,
#           -- OR --
#      project_id: Integer,
#      service_id: Integer,
#      container_id: Integer
#      sftp_id: Integer
#    }
class ClusterAuthService

  attr_accessor :node,
                :project,
                :service,
                :container, # Either SFTP container or Container
                :load_balancer,
                :auth_token

  # Initialize a new ClusterAuthService
  #
  # `data` can be:
  # * json web token, which will be decoded and a hash returned
  # * Node -- This will generate a new JWT for that node
  # * Container -- This will generate a new JWT for that container.
  # * SFTP Container -- This will generate a new JWT for that SFTP container
  #
  #
  def initialize(data = nil)
    return nil if data.nil?
    if data.is_a?(Node)
      self.node = data
      self.auth_token = generate_auth_token!
    elsif data.is_a?(LoadBalancer)
      self.load_balancer = data
      self.auth_token = generate_auth_token!
    elsif data.is_a?(Deployment::Container)
      self.node = nil
      self.container = data
      self.project = data.deployment
      self.service = data.service
      self.auth_token = generate_auth_token!
    elsif data.is_a?(Deployment::Sftp)
      self.node = nil
      self.container = data
      self.project = data.deployment
      self.service = nil
      self.auth_token = generate_auth_token!
    elsif data.is_a?(String)
      load_from_payload!(data)
      self.auth_token = nil
    else
      self.node = nil
      self.auth_token = nil
    end
  end

  def generate_auth_token!
    headers = {}
    d = {}
    if node
      d = {node_id: self.node.id}
      headers[:exp] = 20.minutes.from_now
    elsif container
      d = {
        project_id: self.project&.id,
        service_id: self.service&.id,
      }
      if self.container.is_a?(Deployment::Container)
        d[:container_id] = self.container.id
      elsif self.container.is_a?(Deployment::Sftp)
        d[:sftp_id] = self.container.id
      else
        return nil # Shouldnt be here
      end
    end
    d[:load_balancer_id] = load_balancer.id if load_balancer
    return nil if d.nil?
    d[:nonce] = SecureRandom.urlsafe_base64
    JWT.encode(d, Rails.application.secrets.secret_key_base, 'HS256', headers)
  end

  def load_from_payload!(payload)
    response = decoded_payload(payload)
    if response[:load_balancer_id]
      self.load_balancer = LoadBalancer.find_by(id: response[:load_balancer_id])
    end
    if response[:node_id]
      self.node = Node.find_by(id: response[:node_id])
    else
      self.node = nil
      self.project = Deployment.find_by(id: response[:project_id])
      if response[:container_id]
        self.service = self.project.services.find_by(id: response[:service_id])
        self.container = self.service.containers.find_by(id: response[:container_id])
      else
        self.service = nil
        self.container = self.project.sftp_containers.find_by(id: response[:sftp_id])
      end
    end
  rescue
    nil
  end

  def decoded_payload(payload)
    body = JWT.decode(payload, Rails.application.secrets.secret_key_base, true, { algorithm: 'HS256' })
    if body[1]['exp']
      return nil if Time.parse(body[1]['exp']) < Time.now
    end
    HashWithIndifferentAccess.new body[0]
  rescue
    nil
  end

end
