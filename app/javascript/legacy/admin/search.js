/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/main/docs/suggestions.md
 */
jQuery(function() {
  $('#admin-search-form').focus(function() {
    $(this).attr('placeholder', '');
  });

  $('#admin-search-form').blur(function() {
    $(this).attr('placeholder', $(this).attr('data-placeholder'));
  });
});
