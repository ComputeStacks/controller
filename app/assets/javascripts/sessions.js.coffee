jQuery ->
  # $("input#session-login-form-btn").click ->
  #   $(this).val($(this).attr('data-locale'))
  #   $("form#new_user").submit()
  #   $(this).attr "disabled", "disabled"
  $('#loginModal').modal
    show: true
    backdrop: false
  $('#logoutModal').modal
    show: true
    backdrop: false
  $('#passwordResetNewModal').modal
    show: true
    backdrop: false
  $('#passwordResetEditModal').modal
    show: true
    backdrop: false
