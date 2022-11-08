class TimeHelpers

  class << self

    # Returns the last day, to the second.
    def last_day_of_month(tz = 'UTC')
      last_day_of_given_month DateTime.now, tz
    end

    # @param [DateTime] timestamp
    # @param [String] tz
    def last_day_of_given_month(timestamp, tz = 'UTC')
      d = timestamp.utc.end_of_month
      Time.new d.year, d.month, d.day, 23, 59, 59, tz
    end

    # Returns the first day of the next month, to the second
    def next_month(tz = 'UTC')
      d = DateTime.now.utc.end_of_month + 1.day
      Time.new d.year, d.month, 1, 00, 00, 00, tz
    end

    # Returns first day of this month, to the second.
    def first_day_of_month(tz = 'UTC')
      Time.new Date.today.year, Date.today.month, 1, 00, 00, 00, tz
    end

    # Given two dates, determine the difference per-hour.
    # @param [DateTime] period_start
    # @param [DateTime] period_end
    # @param [Integer] precision
    def fractional_compare(period_start, period_end, precision = 4)
      ((period_end - period_start).to_f / 1.hour).round(precision)
    end

  end

end
