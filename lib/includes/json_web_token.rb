# @deprecated
class JsonWebToken

  class << self

    def encode(payload, jwt_key = Rails.application.secrets.secret_key_base)
      payload.reverse_merge!(meta)
      JWT.encode(payload, jwt_key, 'HS256')
    end

    def decode(token, jwt_key = Rails.application.secrets.secret_key_base)
      body = JWT.decode(token, jwt_key, true, { algorithm: 'HS256' })[0]
      HashWithIndifferentAccess.new body
    rescue
      nil
    end

    def valid_payload(payload)
      if expired(payload) || payload['iss'] != meta[:iss] || payload['aud'] != meta[:aud]
        false
      else
        true
      end
    end

    def meta
      {
        exp: 30.minutes.from_now.to_i,
        iat: Time.now.to_i,
        iss: 'computestacks',
        aud: 'client',
      }
    end

    def expired(payload)
      Time.at(payload['exp']) < Time.now
    end

  end

end
