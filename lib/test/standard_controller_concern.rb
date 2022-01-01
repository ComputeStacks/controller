module StandardTestControllerBase
  
  def before_setup
    super
    Feature.setup!
  end
    
end