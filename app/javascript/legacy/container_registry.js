/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/main/docs/suggestions.md
 */
jQuery(function() {
  if ($("#container-registry-list").length) {
    const registry_list_url = "/container_registry?js=true";
    $("#container-registry-list").load(registry_list_url);
    setInterval((() => $("#container-registry-list").load(registry_list_url)), 5000);
  }
});
