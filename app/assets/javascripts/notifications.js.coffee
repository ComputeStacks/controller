jQuery ->
  $(".notification_select_all_rules").change ->
    $(".notification_rule_boxes").prop "checked", $(this).is(":checked")
    return
