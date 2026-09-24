module HTTParty
  class Response
    def is_ok?
      (self && (code == 200 || code == 201 || code == 204)) ? true : false
    end
  end

  # class Parser
  #   protected
  #   def json
  #     if MultiJson.respond_to?(:adapter)
  #       MultiJson.load(body) rescue {}
  #     else
  #       MultiJson.decode(body) rescue {}
  #     end
  #   end
  # end
end
