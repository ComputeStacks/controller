##
# App Settings

# name:string must be unique.
# category:string
# description:string - Visible to the user
# value:text
#
class Setting < ApplicationRecord

  include Auditable

  scope :sorted, -> { order(:category, :name) }
  scope :display_list, -> { where(Arel.sql %Q(category is not null AND category != 'general')) }
  scope :general_settings, -> { where category: 'general' }

  # Exclude certain categories from being visible in the demo
  scope :excluded_for_demo, -> { where(Arel.sql %Q(category is not null and category not in ('general','mail','belco','google_analytics','container_registry') )) }

  validates :name, uniqueness: true

  before_save :set_value

  after_update_commit :check_billing_module

  after_update_commit :plugin_changes

  def decrypted_value
    (value.blank? || !encrypted) ? value : Secret.decrypt!(value)
  end

  def is_boolean?
    %w(t f).include? value
  end

  # Toggle the current value
  def toggle_val!
    return false unless is_boolean?
    value == 'f' ? update(value: 't') : update(value: 'f')
  end

  class << self

    def enable_signup_form?
      s = Setting.find_by(name: 'signup_form')
      if s.nil?
        s = Setting.create!(
          name: 'signup_form',
          category: 'general',
          description: 'Turn on Registration form',
          value: true
        )
      end
      ActiveRecord::Type::Boolean.new.cast s.value
    end

    ##
    # Billing Module
    #
    #
    def billing_module
      result = {
        'klass' => 'none',
        'params' => {},
        'hooks' => []
      }
      settings = []
      mod = Setting.find_by(name: 'billing_module')
      if mod.nil?
        mod = Setting.create!(
          name: 'billing_module',
          category: 'billing_module',
          description: 'Billing Integration',
          value: nil,
          encrypted: false
        )
      end
      if mod.value.blank? || mod.value.downcase == 'none'
        # Load default settings
        config = {}
        key_namespace = "none"
      else
        result['klass'] = mod.value

        if mod.value == 'Whmcs' && enable_signup_form?
          Setting.find_by(name: 'signup_form').update_column :value, false
        end

        begin
          config = eval(mod.value).config
        rescue
          # Invalid Class Name
          mod.update value: 'none'
        end
        full_config = eval(mod.value).settings
        key_namespace = mod.value.parameterize
        full_config.each do |i|
          key_name = "#{key_namespace}_#{i[:name]}"
          s = Setting.find_by(name: key_name, category: 'billing_module')
          if s.nil?
            desc = i[:label]
            desc = "#{desc} | #{i[:description]}" unless i[:description].blank?
            setting_value = if config[i[:name]].nil?
                              i[:default].blank? ? nil : i[:default]
                            else
                              config[i[:name]]
                            end
            s = Setting.create!(
              name: key_name,
              category: 'billing_module',
              description: desc,
              value: setting_value,
              encrypted: i[:field_type] == 'password'
            )
          end
          settings << s
        end
      end
      result['params'] = settings
      result
    end

    def billing_module_connected?
      bm = billing_module
      return nil if bm['klass'] == 'none'
      bm = Setting.billing_module
      bm_settings_hash = bm['params'].inject({}) do |h, i|
        config_key = i.name.gsub("#{bm['klass'].parameterize}_", '')
        h.merge(config_key.to_sym => i.decrypted_value)
      end
      eval("#{bm['klass']}").configure(bm_settings_hash)
      eval("#{bm['klass']}").test_connection!
    end

    # Currently only supports our whmcs module
    # eventually this should dynamically load hooks from the module
    def billing_hooks
      return [] unless Setting.billing_module['klass'] == 'Whmcs'
      %i(
        process_usage
        user_created
        user_updated
      )
    end

    def call_billing_hook(hook, data)
      bm = Setting.billing_module
      bm_settings_hash = bm['params'].inject({}) do |h, i|
        config_key = i.name.gsub("#{bm['klass'].parameterize}_", '')
        h.merge(config_key.to_sym => i.decrypted_value)
      end
      eval("#{bm['klass']}").configure(bm_settings_hash)
      h = eval("#{bm['klass']}::Hooks.new")
      result = h.send(hook, data)
      unless result
        SystemEvent.create!(
          message: "BillingHook Error: #{hook}",
          log_level: 'warn',
          data: {
            'error' => h.errors
          },
          event_code: 'c8790faff43099b1'
        )
      end
      result
    rescue => e
      ExceptionAlertService.new(e, 'e648b51c1ebbf4db').perform
      SystemEvent.create!(
        message: "BillingHook Fatal Error",
        log_level: 'warn',
        data: {
          'hook' => hook.to_s,
          'error' => e.message.to_s
        },
        event_code: 'e648b51c1ebbf4db'
      )
      false
    end

    def billing_address
      s = Setting.find_by(name: 'billing_address')
      if s.nil?
        s = Setting.create!(
          name: 'billing_address',
          category: 'billing',
          description: 'Enables or Disables Address fields during user registration',
          value: false,
          encrypted: false
        )
      end
      ActiveRecord::Type::Boolean.new.cast s.value
    end

    def billing_phone
      s = Setting.find_by(name: 'billing_phone')
      if s.nil?
        s = Setting.create!(
          name: 'billing_phone',
          category: 'billing',
          description: 'Enables or Disables phone number field during user registration',
          value: false,
          encrypted: false
        )
      end
      ActiveRecord::Type::Boolean.new.cast s.value
    end

    ##
    # =Billing Event Webhook
    def webhook_billing_event
      s = Setting.find_by(name: 'webhook_billing_event')
      if s.nil?
        s = Setting.create!(
          name: 'webhook_billing_event',
          category: 'webhooks',
          description: 'Webhook triggered whenever a billing even takes place.',
          value: nil, # URL of endpoint
          encrypted: false
        )
      end
      s
    end

    ##
    # Billing Usage Web Hook
    def webhook_billing_usage
      s = Setting.find_by(name: 'webhook_billing_usage')
      if s.nil?
        s = Setting.create!(
          name: 'webhook_billing_usage',
          category: 'webhooks',
          description: 'Webhook for capturing billing usage (1 per month)',
          value: nil, # URL of endpoint
          encrypted: false
        )
      end
      s
    end

    ##
    # User Web Hook.
    #
    # Records all changes.
    #
    def webhook_users
      s = Setting.find_by(name: 'webhook_users')
      if s.nil?
        s = Setting.create!(
          name: 'webhook_users',
          category: 'webhooks',
          description: 'Webhook triggered whenever a user is created, updated, or deleted.',
          value: nil, # URL of endpoint
          encrypted: false
        )
      end
      s
    end

    ##
    # General
    def general_support_line
      s = Setting.find_by(name: 'general_support')
      if s.nil?
        s = Setting.create!(
          name: 'general_support',
          category: 'general',
          description: "Generic email support address.",
          value: 'change@me.com',
          encrypted: false
        )
      end
      s.value
    end

    def company_name
      s = Setting.find_by(name: 'company_name')
      if s.nil?
        s = Setting.create!(
          name: 'company_name',
          description: "Company Name",
          category: 'general',
          value: 'ComputeStacks'
        )
      end
      s.value
    end

    def hostname
      s = Setting.find_by(name: 'hostname', category: 'general')
      s = Setting.create!(name: 'hostname', category: 'general', description: 'Main site URL.', value: 'portal.example.com') if s.nil?
      s.value
    end

    def app_name
      s = Setting.find_by(name: 'app_name', category: 'general')
      s = Setting.create!(name: 'app_name', category: 'general', description: 'Name of app used in browser and emails', value: 'ComputeStacks') if s.nil?
      s.value
    end

    ##
    # Belco
    def belco_enabled?
      s = Setting.find_by(name: 'belco', category: 'belco')
      s = Setting.create!(name: 'belco', description: 'Enable Belco.IO Integration?', category: 'belco', value: false) if s.nil?
      ActiveRecord::Type::Boolean.new.cast s.value
    end

    def belco_api_key
      s = Setting.find_by(name: 'belco_api_key', category: 'belco')
      Setting.create!(name: 'belco_api_key', description: 'Belco API ID', category: 'belco', value: nil) if s.nil?
      s.nil? ? nil : s.value
    end

    def belco_shared_secret
      s = Setting.find_by(name: 'belco_shared_secret', category: 'belco')
      Setting.create!(name: 'belco_shared_secret', description: 'Belco API Secret', category: 'belco', encrypted: true, value: nil) if s.nil?
      s.nil? ? nil : s.decrypted_value
    end

    ##
    # Google Analytics
    def google_analytics_enabled?
      s = Setting.find_by(name: 'google_analytics', category: 'google_analytics')
      s = Setting.create!(name: 'google_analytics', description: 'Enable Google Analytics?', category: 'google_analytics', value: false) if s.nil?
      ActiveRecord::Type::Boolean.new.cast s.value
    end

    def google_analytics
      s = Setting.find_by(name: 'google_analytics_id', category: 'google_analytics')
      Setting.create!(name: 'google_analytics_id', description: 'Google Analytics ID', category: 'google_analytics', value: nil) if s.nil?
      s.nil? ? nil : s.value
    end

    ##
    # Branding
    def branding_img_admin
      s = Setting.find_by(name: 'branding_img_admin', category: 'branding')
      s = Setting.create!(name: 'branding_img_admin', category: 'branding', description: "filename for admin logo") if s.nil?
      s.nil? || s.value.blank? ? nil : s.value
    end

    def branding_img_app
      s = Setting.find_by(name: 'branding_img_app', category: 'branding')
      s = Setting.create!(name: 'branding_img_app', category: 'branding', description: "filename for admin logo") if s.nil?
      s.nil? || s.value.blank? ? nil : s.value
    end

    def branding_img_login
      s = Setting.find_by(name: 'branding_img_login', category: 'branding')
      s = Setting.create!(name: 'branding_img_login', category: 'branding', description: "filename for admin logo", value: 'logo-login.png') if s.nil?
      s.nil? || s.value.blank? ? nil : s.value
    end

    def branding_email_logo
      s = Setting.find_by(name: 'branding_email_logo', category: 'branding')
      s = Setting.create!(name: 'branding_email_logo', category: 'branding', description: "URL for the image, or data:image/png value.", value: '') if s.nil?
      s.nil? || s.value.blank? ? nil : s.value
    end

    def ssh_motd
      s = Setting.find_by(name: 'ssh_motd', category: 'branding')
      s = Setting.create!(
        name: 'ssh_motd',
        category: 'branding',
        description: 'Welcome message displayed when connecting to the ssh container',
        value: %Q(SSH Bastion\r\n\r\n     Project: {{ project_name }}\r\n      Region: {{ region }}\r\n          AZ: {{ availability_zone }}\r\n\r\nInstalled tools: composer, git, node, npm, mysql-cli, psql, wp-cli, yarn.\r\n\r\n)
      ) if s.nil?
      s.value
    end

    ##
    # Registry Host
    def registry_node
      s = Setting.find_by(name: 'registry_node', category: 'container_registry')
      s = Setting.create!(name: 'registry_node', description: 'Registry Server IP Address', category: 'container_registry') if s.nil?
      s.value
    end

    def registry_base_url
      s = Setting.find_by(name: 'registry_base_url', category: 'container_registry')
      s = Setting.create!(name: 'registry_base_url', description: 'Base URL', category: 'container_registry') if s.nil?
      s.value
    end

    def registry_ssh_port
      s = Setting.find_by(name: 'registry_ssh_port', category: 'container_registry')
      s = Setting.create!(name: 'registry_ssh_port', description: 'SSH Port', category: 'container_registry', value: '22') if s.nil?
      s.value
    end

    def registry_selinux
      s = Setting.find_by(name: 'registry_selinux', category: 'container_registry')
      s = Setting.create!(name: 'registry_selinux', description: 'Registry server uses selinux?', category: 'container_registry', value: true) if s.nil?
      ActiveRecord::Type::Boolean.new.cast s.value
    end

    ##
    # Helper Methods to determine application state.
    #

    # Quick find
    def lookup(key_name)
      s = Setting.find_by(name: key_name)
      return nil if s.nil?
      s.encrypted ? Secret.decrypt!(s.value) : s.value
    end

    # Whether or not CR uses lets encrypt. And if so, what domain.
    def computestacks_cr_le
      s = Setting.find_by(name: 'cr_le', category: 'computestacks')
      s.update_column(:category, 'container_registry') if s
      s = Setting.find_by(name: 'cr_le', category: 'container_registry') if s.nil?
      if s.nil?
        s = Setting.create!(
          name: 'cr_le',
          category: 'container_registry',
          description: 'Use LetsEncrypt for Container Registry. Value should be the domain used.',
          value: nil, # cr.mydomain.net
          encrypted: false
        )
      end
      s
    end

    ##
    # ComputeStacks Bastion Image
    def computestacks_bastion_image
      s = Setting.find_by(name: 'cs_bastion_image', category: 'computestacks')
      if s.nil?
        s = Setting.create!(
          name: 'cs_bastion_image',
          category: 'computestacks',
          description: 'ComputeStacks Bastion Image',
          value: 'ghcr.io/computestacks/cs-docker-bastion:v2',
          encrypted: false
        )
      end
      s.value
    end

    # LetsEncrypt
    def le
      s = Setting.find_by(name: 'le', category: 'lets_encrypt')
      if s.nil?
        s = Setting.create!(
          name: 'le',
          category: 'lets_encrypt',
          description: 'Enable or Disable Lets Encrypt',
          value: true,
          encrypted: false
        )
      end
      ActiveRecord::Type::Boolean.new.cast s.value
    end

    # Quick way to temporarily disable certificate generation.
    # It will still schedule the job, but won't run it
    def le_auto_enabled?
      s = Setting.find_by(name: 'le_auto', category: 'lets_encrypt')
      if s.nil?
        s = Setting.create!(
          name: 'le_auto',
          category: 'lets_encrypt',
          description: 'Enable Lets Encrypt Scheduled Job',
          value: true,
          encrypted: false
        )
      end
      ActiveRecord::Type::Boolean.new.cast s.value
    end

    def le_server
      s = Setting.find_by(name: 'le_validation_server', category: 'lets_encrypt')
      if s.nil?
        s = Setting.create!(
          name: 'le_validation_server',
          category: 'lets_encrypt',
          description: 'The direct IP & port of the controller, accessible from the nodes',
          value: "localhost:3000",
          encrypted: false
        )
      end
      s.value
    end

    # @return [Integer]
    def le_domains_per_account
      s = Setting.find_by(name: 'le_domains_per_account', category: 'lets_encrypt')
      if s.nil?
        s = Setting.create!(
          name: 'le_domains_per_account',
          category: 'lets_encrypt',
          description: 'How many certificates to place under a single LE Account? 150 min.',
          value: "300",
          encrypted: false
        )
      end
      (s.value.blank? || s.value.to_i < 150) ? 150 : s.value.to_i
    end

    # @return [Boolean]
    def le_single_domain?
      s = Setting.find_by(name: 'le_single_domain', category: 'lets_encrypt')
      if s.nil?
        s = Setting.create!(
          name: 'le_single_domain',
          category: 'lets_encrypt',
          description: 'Use 1 domain per certificate, rather than combining. Please note https://letsencrypt.org/docs/rate-limits',
          value: false,
          encrypted: false
        )
      end
      ActiveRecord::Type::Boolean.new.cast s.value
    end

    # @return [Integer]
    def le_dns_sleep
      s = Setting.find_by(name: 'le_dns_sleep', category: 'lets_encrypt')
      if s.nil?
        s = Setting.create!(
          name: 'le_dns_sleep',
          category: 'lets_encrypt',
          description: 'How long to wait (in seconds) before verifying DNS with wildcard certificates. Min 2, Max 90.',
          value: "10",
          encrypted: false
        )
      end
      v = s.value.to_i
      return 2 if v < 2
      v > 90 ? 90 : v
    end

    def monarx_init!
      monarx_enabled?
      monarx_agent_key
      monarx_agent_secret
      monarx_api_key
      monarx_api_secret
      monarx_enterprise_id

      unless ContainerImagePlugin.where(name: 'monarx').exists?
        ContainerImagePlugin.create! name: 'monarx', active: false
      end

    end


    def monarx_enabled?
      s = Setting.find_by name: 'monarx_active', category: 'plugins'
      if s.nil?
        s = Setting.create!(
          name: 'monarx_active',
          category: 'plugins',
          description: 'Enable Monarx',
          value: 'f',
          encrypted: false
        )
      end
      ActiveRecord::Type::Boolean.new.cast s.value
    end

    def monarx_api_key
      s = Setting.find_by name: 'monarx_api_key', category: 'plugins'
      if s.nil?
        s = Setting.create!(
          name: 'monarx_api_key',
          category: 'plugins',
          description: "Monarx API Key",
          value: "",
          encrypted: true
        )
      end
      s.value.blank? ? nil : Secret.decrypt!(s.value)
    end

    def monarx_api_secret
      s = Setting.find_by name: 'monarx_api_secret', category: 'plugins'
      if s.nil?
        s = Setting.create!(
          name: 'monarx_api_secret',
          category: 'plugins',
          description: "Monarx API Secret",
          value: "",
          encrypted: true
        )
      end
      s.value.blank? ? nil : Secret.decrypt!(s.value)
    end

    def monarx_agent_key
      s = Setting.find_by name: 'monarx_agent_key', category: 'plugins'
      if s.nil?
        s = Setting.create!(
          name: 'monarx_agent_key',
          category: 'plugins',
          description: "Monarx Agent Key",
          value: "",
          encrypted: true
        )
      end
      s.value.blank? ? nil : Secret.decrypt!(s.value)
    end

    def monarx_agent_secret
      s = Setting.find_by name: 'monarx_agent_secret', category: 'plugins'
      if s.nil?
        s = Setting.create!(
          name: 'monarx_agent_secret',
          category: 'plugins',
          description: "Monarx Agent Secret",
          value: "",
          encrypted: true
        )
      end
      s.value.blank? ? nil : Secret.decrypt!(s.value)
    end

    def monarx_enterprise_id
      s = Setting.find_by name: 'monarx_enterprise_id', category: 'plugins'
      if s.nil?
        s = Setting.create!(
          name: 'monarx_enterprise_id',
          category: 'plugins',
          description: "Monarx Enterprise ID",
          value: "",
          encrypted: false
        )
      end
      s.value.blank? ? nil : s.value
    end

    ##
    # SMTP
    def smtp_init!
      smtp_from
      s_server = Setting.find_by(name: 'smtp_server', category: 'mail')
      Setting.create!(name: 'smtp_server', category: 'mail', description: 'SMTP Server', value: 'smtp.postmarkapp.com') if s_server.nil?
      s_port = Setting.find_by(name: 'smtp_port', category: 'mail')
      Setting.create!(name: 'smtp_port', category: 'mail', description: 'SMTP Port', value: '2525') if s_port.nil?
      s_auth_username = Setting.find_by(name: 'smtp_username', category: 'mail')
      Setting.create!(name: 'smtp_username', category: 'mail', description: 'SMTP Username', value: 'example') if s_auth_username.nil?
      s_auth_password = Setting.find_by(name: 'smtp_password', category: 'mail')
      Setting.create!(name: 'smtp_password', category: 'mail', description: 'SMTP Password', value: 'example', encrypted: true) if s_auth_password.nil?
    end

    def smtp_from
      s = Setting.find_by(name: 'smtp_from', category: 'mail')
      s = Setting.create!(name: 'smtp_from', category: 'mail', description: 'From Address', value: 'noreply@example.com') if s.nil?
      s.value
    end

    def smtp_configured?
      smtp_from != "noreply@example.com"
    end

    def marketplace_username
      s = Setting.find_by name: 'marketplace_username', category: 'plugins'
      if s.nil?
        s = Setting.create!(
          name: 'marketplace_username',
          category: 'plugins',
          description: "Username for Marketplace Plugins",
          value: "",
          encrypted: false
        )
      end
      s.value.blank? ? nil : s.value
    end

    def marketplace_password
      s = Setting.find_by name: 'marketplace_password', category: 'plugins'
      if s.nil?
        s = Setting.create!(
          name: 'marketplace_password',
          category: 'plugins',
          description: "Password for Marketplace Plugins",
          value: "",
          encrypted: true
        )
      end
      s.value.blank? ? nil : s.decrypted_value
    end

    # Load all other defaults (not including above.)
    def setup!
      # DISABLED
      #
      # billing_order_redirect
      # webhook_billing_event
      # webhook_users
      #
      %w(
        app_name
        belco_enabled?
        belco_api_key
        belco_shared_secret
        billing_address
        billing_hooks
        billing_module
        billing_phone
        branding_img_admin
        branding_img_app
        branding_img_login
        branding_email_logo
        company_name
        computestacks_bastion_image
        computestacks_cr_le
        enable_signup_form?
        general_support_line
        google_analytics_enabled?
        google_analytics
        hostname
        le
        le_auto_enabled?
        le_domains_per_account
        le_dns_sleep
        le_server
        le_single_domain?
        marketplace_username
        marketplace_password
        monarx_init!
        registry_base_url
        registry_node
        registry_selinux
        registry_ssh_port
        smtp_init!
        ssh_motd
        webhook_billing_event
        webhook_billing_usage
        webhook_users
      ).each do |i|
        eval("Setting::#{i}")
      end
      true
    end

  end

  private

  def set_value
    if self.encrypted && !self.value.blank?
      self.value = Secret.encrypt!(self.value)
    elsif self.name == 'billing_module'
      self.value = value.blank? ? 'none' : value.capitalize.strip
    end
    # Remove leading HTTP(s).
    self.value = self.value.gsub("http://", "").gsub("https://", "").strip if self.name == 'hostname'
  end

  def check_billing_module
    Setting.billing_module if self.name == 'billing_module'
  end

  def plugin_changes
    return unless category == 'plugins'

    # Monarx: Update visibility based on Settings.
    if name =~ /monarx/ && ContainerImagePlugin.monarx.exists?
      monarx_plugin = ContainerImagePlugin.monarx.first
      unless monarx_plugin.active == monarx_plugin.monarx_available?
        monarx_plugin.update active: monarx_plugin.monarx_available?
      end
    end

  end

end
