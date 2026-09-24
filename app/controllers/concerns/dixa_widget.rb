module DixaWidget
  extend ActiveSupport::Concern

  included do
    before_action :load_dixa_key
  end

  private

  def load_dixa_key
    @dixa_support_key = if current_user && Setting.dixa_enabled?
      Setting.dixa_api_key
    end
  end
end
