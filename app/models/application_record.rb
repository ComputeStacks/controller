class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  def global_id
    to_global_id.to_s
  end

  ##
  # A process to surface context up to our logging system.
  def context
    @context.nil? ? {} : @context
  end

  def context=(d)
    unless d.is_a?(Hash)
      raise "must be a hash"
    end
    @context = d
  end

  def add_context!(d = {})
    unless d.is_a?(Hash)
      raise "must be a hash"
    end
    return d if d.empty?
    if @context.nil?
      @context = d
    else
      @context.merge! d
    end
  end

  def why?
    context
  end

end
