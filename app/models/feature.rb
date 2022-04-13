class Feature < ApplicationRecord

  has_and_belongs_to_many :users

  class << self

    def using_clustered_storage?
      Region.where.not(volume_backend: 'local').exists?
    end

    # Check for permission
    def check(name, user = nil)
      feature = Feature.find_by(name: name)
      if feature.nil?
        false
      elsif feature.active
        true
      elsif user.nil?
        false
      else
        feature.users.include?(user)
      end
    end

    # Check if feature is in maintenance mode
    def maintenance(name)
      feature = Feature.find_by(name: name)
      return true if feature.nil? || feature.maintenance
      false
    end

    def setup!
      feature_list = [
        { 'feature' => 'admin', 'default' => true },
        { 'feature' => 'auth_seckey', 'default' => true },
        { 'feature' => 'backups', 'default' => true },
        { 'feature' => 'collect_user_info', 'default' => false },
        { 'feature' => 'demo', 'default' => false }, # demo.computestacks.net
        { 'feature' => 'dns', 'default' => true },
        { 'feature' => 'exception_user_info', 'default' => false }, # Include email and user's name in Sentry
        { 'feature' => 'log_iptables', 'default' => false },
        { 'feature' => 'loki', 'default' => true },
        { 'feature' => 'loki_fluentd', 'default' => true },
        { 'feature' => 'updated_cr_cert', 'default' => true },
        { 'feature' => 'tcp_iptables', 'default' => true },
        { 'feature' => 'wp_beta', 'default' => false }, # Wordpress Beta Features
        { 'feature' => 'setting_belco', 'default' => false } # Show belco options
      ]
      feature_list.each do |i|
        unless Feature.where(name: i['feature']).first
          Feature.create!(name: i['feature'], maintenance: false, active: i['default'])
        end
      end
      # Cleanup unused feature flags
      current_flags = feature_list.map { |i| i['feature'] }
      Feature.all.each do |i|
        i.destroy unless current_flags.include?(i.name)
      end
    end

    # END setup!

  end

end
