/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/main/docs/suggestions.md
 */
jQuery(function() {
  // $("input#session-login-form-btn").click ->
  //   $(this).val($(this).attr('data-locale'))
  //   $("form#new_user").submit()
  //   $(this).attr "disabled", "disabled"
  $('#loginModal').modal({
    show: true,
    backdrop: false
  });
  $('#logoutModal').modal({
    show: true,
    backdrop: false
  });
  $('#passwordResetNewModal').modal({
    show: true,
    backdrop: false
  });
  return $('#passwordResetEditModal').modal({
    show: true,
    backdrop: false
  });
});
