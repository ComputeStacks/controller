/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/main/docs/suggestions.md
 */
jQuery(() => $("form#api-credentials-generate").submit(function() {
  const waiting = $("button#api-credentials-generate-btn").attr('data-locale') + '...';
  $("button#api-credentials-generate-btn").html(waiting).attr("disabled", "disabled");
}));
