/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/main/docs/suggestions.md
 */
jQuery(() => $("#volumeCreateBackup").on("hidden.bs.modal", function() {
  $("input#backupName").val("");
}));