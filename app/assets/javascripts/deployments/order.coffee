setContainerPackage = ->

  $('button.container-package-selection').each ->
    choose_text = $(this).attr('data-choose')
    $(this).removeClass 'btn-info'
    $(this).addClass 'btn-default'
    $(this).removeAttr 'disabled'
    $(this).html choose_text

  $('input.container-package-input').each (i,v) ->
    selected_btn = 'button#cpackage-btn-' + $(v).attr('data-index') + '-' + $(v).attr('value')
    selected_text = $(selected_btn).attr('data-selected')
    $(selected_btn).addClass 'btn-info'
    $(selected_btn).removeClass 'btn-default'
    $(selected_btn).attr 'disabled', 'disabled'
    $(selected_btn).html selected_text

jQuery ->
  if $('.container-package-selection').length
    setContainerPackage()

  $('.container-package-selection').click ->
    package_id = $(this).attr('data-package-id')
    input_element = 'input#p' + $(this).attr('data-i')
    $(input_element).val package_id
    setContainerPackage()