module HTTParty

  class Response
    def is_ok?
      self && (self.code == 200 || self.code == 201 || self.code == 204) ? true : false
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
