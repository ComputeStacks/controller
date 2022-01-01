# encoding : utf-8

MoneyRails.configure do |config|
  config.default_currency = ENV['CURRENCY'].parameterize.underscore.to_sym
end
