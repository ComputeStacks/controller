$.fn.clearForm = ->
  @each ->
    type = @type
    tag = @tagName.toLowerCase()
    return $(":input", this).clearForm()  if tag is "form"
    if type is "text" or type is "password" or tag is "textarea"
      @value = ""
    else if type is "checkbox" or type is "radio"
      @checked = false
    else @selectedIndex = -1  if tag is "select"

jQuery ->
  $("button.mailbox-form-cancel-button").click ->
    $(".mailbox-form").clearForm()
    $(".mailbox-form-message").each ->
      $(this).html($(this).attr('data-default'))

  $("#email-user-show").on "hidden", ->
    $("button").each ->
      $(this).attr "disabled", "disabled"
    $("a").click (e) ->
      e.preventDefault()
    window.location = "/email"

  # Plan Chooser
  $("a.email_plan_chooser").click (e) ->
    cost = 0
    plan_input = $(this).attr("data-plan")
    $("input#" + plan_input).attr "checked", "checked"
    obj_id = $(this).attr("data-id")
    $("a.email_plan_chooser").each ->
      $(this).removeAttr "disabled"
      $(this).html "Choose"
      $(this).removeClass "btn-primary"
      $(this).addClass "btn-success"
    plan_cost = Number($("input#" + plan_input).attr('data-cost'))
    cost += plan_cost
    cost = Math.round(cost*100)/100
    $("#email_user_nprice_" + obj_id).html(cost)

    $(this).attr "disabled", "disabled"    
    $(this).html "Selected" 
    $(this).removeClass "btn-success"
    $(this).addClass "btn-primary"
    e.preventDefault()

  $(".edit-mailbox-form").submit ->
    user = $(this).attr "data-id"
    cancel_button = $("button#email-user-cancel-btn-" + user)
    save_button = $("button#email-user-edit-btn-" + user)
    save_button.attr "disabled", "disabled"
    cancel_button.attr "disabled", "disabled"
    save_button.html "Please Wait..."


  $("a.user-reset-password").click (e) ->
    $.get $(this).attr("href"), ((data) ->
      if data.success
        the_image = "<img src='//" + data.image + "' class='img-polaroid' />"
        $("#email-user-show-img").html the_image
        $("#email-user-show-name").html data.email
        $("#email-user-show-pass").html data.password
        $("#email-user-show-header").html "<h3>Successfully Reset Password</h3>"
        $("#email-user-show").modal 'show'
      else
        $("#email-user-show-header").html "<h3>Error during Password Reset</h3>"
        $("#email-user-show-body").html "<p class='lead'>" + data.message + "</p>"
        $("#email-user-show").modal 'show'
    ), "json"
    e.preventDefault()

  $(".new-mailbox-form").submit ->
    form = $(this)
    domain = $(this).attr "data-domain"
    button = $("button#email-new-user-submit-" + domain)
    cancel_button = $("button#email-new-cancel-" + domain)
    button.attr "disabled", "disabled"
    cancel_button.attr "disabled", "disabled"
    button.html "Working.."
    $("input.has-error").removeClass "has-error"
    $.post $(this).attr("action"), $(this).serialize(), ((data) ->
      if data.success
        if data.redirect
          button.removeClass "btn-primary"
          button.addClass "btn-success"
          button.html "Please Wait..."
          window.location = data.redirect
        else
          form.clearForm()
          $(".new-email-user").modal 'hide'
          the_image = "<img src='//" + data.image + "' class='img-polaroid' />"
          $("#email-user-show-img").html the_image
          $("#email-user-show-name").html data.email
          $("#email-user-show-pass").html data.password
          $("#email-user-show").modal 'show'
      else
        button.removeAttr 'disabled'
        cancel_button.removeAttr "disabled"
        button.html "Create Mailbox"
        if data.message
          $("p#error_message_" + domain).html("<span style='color:red;'>" + data.message + "</span>")
        $.each data.fields, (index, value) ->
          $("#" + value).addClass "has-error"

    ), "json"

    false