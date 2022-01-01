String::capitalize = ->
  @charAt(0).toUpperCase() + @slice(1)

jQuery ->
  $("a[rel~=popover], .has-popover").popover()
  $("a[rel~=tooltip], .has-tooltip").tooltip()
  $('[data-toggle="tooltip"]').tooltip()

  if $(".app-flash").length
    $(".app-flash").each ->
      if $(this).hasClass('alert-success') || $(this).hasClass('alert-info')
        $(this).delay(9000).fadeOut('slow')


  # Allow selecting tab with anchor
  hash = window.location.hash
  hash and $('ul.nav.nav-tabs a[href="' + hash + '"]').tab('show')
  $('ul.nav.nav-tabs a').click (e) ->
    $(this).tab 'show'
    scrollmem = $('body').scrollTop()
    window.location.hash = @hash
    return

# $ ->
#   $.rails.confirm = (message) ->
#     $("#confirm_dialog > .modal-dialog > .modal-content > .modal-body").html('<p class="lead">' + message + '</p>')
#     false
#   if $('[data-confirm]')
#     title = $("body").attr('data-modal-title')
#     cancel = $('body').attr('data-modal-cancel')
#     ok = $('body').attr('data-modal-yes')
#     if ok == ''
#       ok = 'Yes'
#     $('body').append("<div class='modal' id='confirm_dialog'><div class='modal-dialog'><div class='modal-content'><div class='modal-header'><h4 class='modal-title'>" + title + "</h4></div><div class='modal-body text-center'></div><div class='modal-footer'><a href='#' data-dismiss='modal' class='btn btn-default cancel_confirm_dialog' style='float:left;'>" + cancel + "</a><a class='btn btn-danger'></a></div></div></div></div>")
#     $('[data-confirm]').each ->
#       link_elem = $(this)
#       link_elem.click (e) ->
#         e.preventDefault()
#         confirm = $('#confirm_dialog > .modal-dialog > .modal-content > .modal-footer > .btn-danger')
#         new_confirm = link_elem.clone()
#         new_confirm.removeAttr('data-confirm id')
#         new_confirm.attr('class', 'btn btn-danger')
#         new_confirm.html(ok)
#         confirm.replaceWith(new_confirm)
#         $('#confirm_dialog').modal()
#         $("#confirm_dialog").on 'hidden.bs.modal', (e) ->
#           window.location.reload false
