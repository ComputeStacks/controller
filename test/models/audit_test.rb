require "test_helper"

class AuditTest < ActiveSupport::TestCase
  # Regression: an Order audit whose Order has been deleted used to send
  # `linked` and `related_linked` into infinite mutual recursion
  # (SystemStackError: stack level too deep) when raw_data was present,
  # 500ing the /admin/audit index. `linked` must resolve to nil instead.
  test "linked returns nil for an Order audit whose order no longer exists" do
    audit = Audit.new(
      event: "created",
      rel_model: "Order",
      rel_uuid: "00000000-0000-0000-0000-000000000000",
      raw_data: {name: "gone"}
    )

    assert_nil audit.linked
    assert_equal [], audit.related_linked
  end
end
