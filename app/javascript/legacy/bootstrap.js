/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/main/docs/suggestions.md
 */
String.prototype.capitalize = function() {
  return this.charAt(0).toUpperCase() + this.slice(1);
};

jQuery(function() {
  $("a[rel~=tooltip], .has-tooltip").tooltip();
  $('[data-toggle="tooltip"]').tooltip();

  if ($(".app-flash").length) {
    $(".app-flash").each(function() {
      if ($(this).hasClass('alert-success') || $(this).hasClass('alert-info')) {
        $(this).delay(9000).fadeOut('slow');
      }
    });
  }


  // Allow selecting tab with anchor
  const {
    hash
  } = window.location;
  hash && $('ul.nav.nav-tabs a[href="' + hash + '"]').tab('show');
  $('ul.nav.nav-tabs a').click(function(e) {
    $(this).tab('show');
    $('body').scrollTop();
    window.location.hash = this.hash;
  });
});
