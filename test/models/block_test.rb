require 'test_helper'

class BlockTest < ActiveSupport::TestCase

  test "should not create block without title" do
    block = Block.new
    assert_not block.save
  end

  test "should create block with title" do
    assert Block.create! title: "test"
  end

  test "should include block content" do
    assert_not Block.first.block_contents.empty?
  end

  test "lookup by locale" do
    assert Block.where("block_contents.locale = 'en'").joins(:block_contents).exists?
  end

end
