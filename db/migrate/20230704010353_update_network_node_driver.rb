class UpdateNetworkNodeDriver < ActiveRecord::Migration[7.0]
  def change
    return unless Rails.env.production?
    ##
    # We added 'Driver' to the nat rule spec. This will ensure consul has that.
    Node.all.each do |node|
      node.update_iptable_config!
    end
  end
end
