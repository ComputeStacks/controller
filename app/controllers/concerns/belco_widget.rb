module BelcoWidget
  extend ActiveSupport::Concern

  included do
    before_action :belco_hmac, if: :current_user
    helper_method :belco_hmac
  end

  private

  def belco_hmac
    @belco_hmac if defined?(@belco_hmac)
    if Setting.belco_enabled? && current_user
      digest = OpenSSL::Digest.new('sha256')
      @belco_hmac = OpenSSL::HMAC::hexdigest(
        digest,
        Setting.belco_shared_secret,
        current_user.id.to_s
      )
    else
      @belco_hmac = ''
    end
  end

end
