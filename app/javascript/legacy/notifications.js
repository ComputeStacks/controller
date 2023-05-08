/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/main/docs/suggestions.md
 */
jQuery(() => $(".notification_select_all_rules").change(function() {
  $(".notification_rule_boxes").prop("checked", $(this).is(":checked"));
}));
