class AddChangelogCursorToNodes < ActiveRecord::Migration[7.2]
  def change
    # High-water mark of the cs-agent changelog `seq` this node's projection has
    # consumed. Single global per-node cursor: one pruning watermark, preserves
    # cross-entity order. `since` is exclusive on the agent side (seq > since).
    add_column :nodes, :changelog_cursor, :bigint, default: 0, null: false
  end
end
