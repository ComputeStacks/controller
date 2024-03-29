module Volumes
  module BorgPolicy
    extend ActiveSupport::Concern

    included do

      before_validation :validate_volume_consul

      validates :borg_keep_hourly, numericality: { only_integer: true, less_than: 25 }
      validates :borg_keep_daily, numericality: { only_integer: true, less_than: 8 }
      validates :borg_keep_weekly, numericality: { only_integer: true, less_than: 5 }
      validates :borg_keep_monthly, numericality: { only_integer: true, less_than: 25 }

      # see: ContainerImages::VolumeParamsHelper.borg_strategies
      validates :borg_strategy, inclusion: { in: %w(custom file mariadb mysql postgres) }

    end

    private

    def validate_volume_consul
      # Validate and manage cron frequency
      self.borg_freq = self.borg_freq.strip
      custom_freq = %w(@hourly @midnight @weekly @monthly @daily)
      unless custom_freq.include?(self.borg_freq)
        parsed = Fugit::Cron.parse(self.borg_freq)
        if parsed.nil?
          errors.add(:cron_freq, "invalid frequency syntax")
        elsif parsed.rough_frequency < 3600 && self.borg_strategy != "file"
          errors.add(:cron_freq, "frequency must not exceed every hour")
        elsif parsed.rough_frequency < 1800 && self.borg_strategy == "file"
          errors.add(:cron_freq, "frequency must not exceed every 30 minutes")
        end
      end
    end

  end
end
