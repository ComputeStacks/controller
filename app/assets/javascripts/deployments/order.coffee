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

setImageVariant = ->

  $('button.image-variant-selector').each ->
    choose_text = $(this).attr('data-choose')
    $(this).removeClass 'btn-info'
    $(this).addClass 'btn-default'
    $(this).removeAttr 'disabled'
    $(this).html choose_text

  $('input.image-variant-input').each (i,v) ->
    selected_btn = 'button#image-variant-btn-' + $(v).attr('data-image') + '-' + $(v).attr('value')
    selected_text = $(selected_btn).attr('data-selected')
    version_label_field = "span#image-variant-label-" + $(v).attr('data-image')
    $(version_label_field).html $(selected_btn).attr('data-label')
    $(selected_btn).addClass 'btn-info'
    $(selected_btn).removeClass 'btn-default'
    $(selected_btn).attr 'disabled', 'disabled'
    $(selected_btn).html selected_text

selectContainerAddons = ->

  $('button.container-addon-selection').each ->
    choose_text = $(this).attr('data-choose')
    $(this).removeClass 'btn-info'
    $(this).addClass 'btn-default'
    $(this).html choose_text

  $('input.container-addon-checkbox').each (i,v) ->
    selected_btn = 'button#cs-addon-btn-' + $(v).attr('data-index') + '-' + $(v).attr('value')
    selected_text = $(selected_btn).attr('data-selected')
    if $(v).attr("checked")
      $(selected_btn).addClass 'btn-info'
      $(selected_btn).removeClass 'btn-default'
      $(selected_btn).html selected_text

jQuery ->

  if $('.image-variant-selector').length
    setImageVariant()

    $('.image-variant-selector').click ->
      input_element = "input#image-" + $(this).attr('data-image') + "-variant"
      $(input_element).val $(this).attr('data-variant')
      setImageVariant()

  if $('.container-addon-selection').length
    selectContainerAddons()

    $('.container-addon-selection').click ->
      addon_id = $(this).attr('data-addon')
      image_variant_id = $(this).attr('data-i')
      input_element = 'input#addon-checkbox-' + image_variant_id + '-' + addon_id
      if $(input_element).attr("checked")
        $(input_element).removeAttr "checked"
      else
        $(input_element).attr "checked", "checked"
      selectContainerAddons()

  if $('.container-package-selection').length
    setContainerPackage()

    $('.container-package-selection').click ->
      package_id = $(this).attr('data-package-id')
      input_element = 'input#p' + $(this).attr('data-i')
      $(input_element).val package_id
      setContainerPackage()
