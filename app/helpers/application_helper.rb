module ApplicationHelper

  def flash_class(type)
    case type
      when 'success'
        'success'
      when 'info', 'notice'
        'info'
      when 'warning'
        'warning'
      else
        'danger'
    end
  end

  # @param [BigDecimal] amount
  # @param [Integer] precision
  def format_currency(amount, precision = 2)
    number_to_currency(amount, unit: Money.new(1, current_user.currency).symbol, precision: precision)
  end

  # Format data sizes
  def size_format(amount, format = "MB")
    if format == "MB"
      amount = amount.to_i
      if amount >= 1024 && amount % 1024 == 0
        return "#{amount / 1024} GB"
      elsif amount < 1024
        return "#{amount} MB"
      else
        return "#{sprintf('%0.1f', (amount / 1024) + ((amount % 1024) / 1024.00))} GB"
      end
    elsif format == "KB"
      amount = amount.to_i
      if amount >= 1000000 && amount % 1000000 == 0
        return "#{amount / 1000000} GB"
      elsif amount >= 1000000
        return "#{sprintf('%0.1f', (amount / 1000000) + ((amount % 1000000) / 1000000.00))} GB"
      elsif amount >= 1024 && amount % 1024 == 0
        return "#{amount / 1024} MB"
      elsif amount < 1024
        return "#{amount} MB"
      else
        return "#{sprintf('%0.1f', (amount / 1024) + ((amount % 1024) / 1024.00))} MB"
      end
    else
      false
    end
  end

  def setting_lookup(name)
    setting = Setting.where(name: name).first
    if setting.nil? || setting.value.nil?
      "Unknown Setting."
    else
      raw(setting.value)
    end
  end

end
