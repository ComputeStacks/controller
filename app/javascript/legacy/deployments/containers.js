/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS208: Avoid top-level this
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/main/docs/suggestions.md
 */

jQuery(function() {

  $("select#container_log_container_select").change(function() {
    const container_id = $(this).val();
    const new_url = "/containers/" + container_id + "/container_logs";
    window.location = new_url;
  });
});
