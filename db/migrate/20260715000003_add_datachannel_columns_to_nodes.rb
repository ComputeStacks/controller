class AddDatachannelColumnsToNodes < ActiveRecord::Migration[7.2]
  def change
    # changelog_acked: durable projection watermark reported to the agent via
    #   POST /v1/admin/changelog/ack. Lets ack lag the cursor without stalling
    #   projection; never rewinds. (changelog_cursor already exists from the pilot.)
    # datachannel_backfilled_at: first-boot sentinel — set once the backfill rake has
    #   PUT this node's firewall + every volume. DOWN task dispatch refuses until set.
    add_column :nodes, :changelog_acked, :bigint, default: 0, null: false
    add_column :nodes, :datachannel_backfilled_at, :datetime
  end
end
