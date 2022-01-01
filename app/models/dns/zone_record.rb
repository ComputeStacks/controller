##
# Dns Zone Record
class Dns::ZoneRecord

  attr_accessor :id,
                :zone,
                :zone_client,
                :type

  # @param [Dns::Zone] zone
  def initialize(id, zone, type = nil)
    self.id = id
    self.zone = zone
    self.type = type
    # \@dns_driver = ProvisionDriver.dns_drivers.first # used for txt verfication. does not work.
  end

  def client
    if self.zone.available_actions.include?('update_by_zone') && !self.id.nil?
      self.zone_client = self.zone.state_load!
      client = self.zone_client.records[self.type][self.id] # self.id = array index.
    elsif self.zone.available_actions.include?('update_by_zone')
      self.zone_client = self.zone.state_load!
      self.zone.provision_driver.zone_record.new(self.zone.provision_driver.service_client, self.id, self.zone.provider_ref)
    else
      begin
        client = self.zone.provision_driver.zone_record.new(self.zone.auth.client, self.id, self.zone.provider_ref)
      rescue
        nil
      else
        client
      end
    end
  end

  def create!(params)
    the_client = client
    if params[:type] == "A"
      begin
        ip_check = IPAddr.new(params[:ip])
      rescue
        return {'success' => false, 'message' => "Invalid IP Address Format."}
      end
      the_client.type = ip_check.ipv6? ? 'AAAA' : 'A'
    else
      the_client.type = params[:type]
    end
    the_client.ttl = params[:ttl]
    the_client.name = params[:name].blank? ? '@' : params[:name]
    the_client.email = params[:email]
    the_client.primary_dns = params[:primary_dns]
    the_client.expire = params[:expire]
    the_client.refresh = params[:refresh]
    the_client.retry = params[:retry]
    the_client.hostname = params[:hostname]
    the_client.ip = params[:ip]
    the_client.priority = params[:priority]
    if the_client.type == 'TXT'
      zone_value = params[:value].gsub('"', '').gsub("'", '')
      the_client.value = zone_value
      # the_client.value = "\"#{zone_value}\""
      # if @dns_driver.has_txt_limit? # Does not work.
      #   if the_client.value.length > 255
      #     return {'success' => false, 'message' => 'TXT value must be less than 255 characters.'}
      #   end
      # end
    else
      the_client.value = params[:value]
    end
    if self.zone.available_actions.include?('update_by_zone')
      the_client.name = format_name(the_client.name)
      the_client.hostname = format_hostname(the_client.hostname) unless the_client.hostname.nil? || the_client.hostname.blank?
      validate!(the_client)
      self.zone_client = self.zone.state_load!
      self.zone_client.records[the_client.type] << the_client
      self.zone.state_save!(self.zone_client)
      {'success' => true}
    else
      begin
        the_client.save
      rescue => e
        ExceptionAlertService.new(e, 'cbd8110a311f6a10').perform
        {'success' => false, 'message' => e.message}
      else
        {'success' => true}
      end
    end
  end

  def update!(params)

    the_client = client
    the_client.ttl = params[:ttl]
    the_client.name = params[:name]
    the_client.email = params[:email]
    the_client.primary_dns = params[:primary_dns]
    the_client.expire = params[:expire]
    the_client.refresh = params[:refresh]
    the_client.retry = params[:retry]
    the_client.hostname = params[:hostname]
    the_client.ip = params[:ip]
    the_client.priority = params[:priority]
    if the_client.type == 'TXT'
      zone_value = params[:value].gsub('"', '').gsub("'", '')
      the_client.value = zone_value
      # the_client.value = "\"#{zone_value}\""
      # if @dns_driver.has_txt_limit? # Does not work.
      #   if the_client.value.length > 255
      #     return {'success' => false, 'message' => 'TXT value must be less than 255 characters.'}
      #   end
      # end
    else
      the_client.value = params[:value]
    end
    if self.zone.available_actions.include?('update_by_zone')
      the_client.name = format_name(the_client.name)
      the_client.hostname = format_hostname(the_client.hostname) unless the_client.hostname.nil? || the_client.hostname.blank?
      validate!(the_client)
      self.zone.state_save!(self.zone_client)
      {'success' => true}
    else
      begin
        the_client.save
      rescue => e
        ExceptionAlertService.new(e, '6e369cd3bb9660fb').perform
        {'success' => false, 'message' => e.message}
      else
        {'success' => true}
      end
    end
  end

  def destroy
    if self.zone.available_actions.include?('update_by_zone')
      return {'success' => false, 'message' => "Missing record type."} if self.type.nil?
      return {'success' => false, 'message' => 'Invalid record ID'} if self.id.nil?
      self.zone_client = self.zone.state_load!
      self.zone_client.records[self.type].delete_at(self.id)
      self.zone.state_save!(self.zone_client)
      {'success' => true}
    else
      begin
        self.client.destroy
      rescue => e
        ExceptionAlertService.new(e, '7c93980e45360e1d').perform
        {'success' => false, 'message' => e.message}
      else
        {'success' => true}
      end
    end
  end

  # Local zone file
  def format_name(name)
    if name == '@' || name == self.zone.name || name == "#{self.zone.name}." || (self.zone.name[-1] == '.' && "#{name}." == self.zone.name)
      self.zone.name[-1] == '.' ? self.zone.name : "#{self.zone.name}."
    else
      a = name.gsub(".#{self.zone.name}.", '').gsub(".#{self.zone.name}", '').gsub("#{self.zone.name}.", '').gsub(self.zone.name, '')
      self.zone.name[-1] == '.' ? "#{a}.#{self.zone.name}" : "#{a}.#{self.zone.name}."
    end
  end

  # Pointing to: CNAME, MX.
  def format_hostname(hostname)
    a = hostname.strip
    a[-1] == '.' ? a : "#{a}."
  end

  # Check!
  def validate!(params)
    if params.type == 'CNAME'
      return {'success' => false, 'message' => "Can't create CNAME on root domain."} if params.name == "#{self.zone.name}."
    end
  end

end
