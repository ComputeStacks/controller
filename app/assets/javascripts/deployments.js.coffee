jQuery ->

  # order
  $('.container-package-selector').click ->
    cid = $(this).attr('data-id')
    pid = 'p' + cid
    $('input#' + pid).val $(this).attr('data-package')
    $("a[data-id='" + cid + "']").each ->
      $(this).removeClass 'active'
    $(this).addClass 'active'
    false

  # Prevent de-selection of image when changing variant
  $('select.order-variant-selector').click (e) ->
    cid = $(this).attr('data-id')
    pid = "#image_" + cid
    if $(pid).hasClass('active')
      return e.stopPropagation()

  # Selecting a variant should select the image.
  $('select.order-variant-selector').change ->
    cid = $(this).attr('data-id')
    pid = "#image_" + cid
    el = document.querySelector pid
    if !$(pid).hasClass('active')
      newEvent = new Event("click")
      return el.dispatchEvent(newEvent)

  $('.container-image-selector').click ->
    the_element = $(this).attr('data-id')
    required_images = $.parseJSON($(this).attr('data-required'))
    if $(this).hasClass('active')
      $(this).removeClass 'active'
      $("input#container-" + the_element).prop 'checked', false
    else
      $(this).addClass 'active'
      $("input#container-" + the_element).prop 'checked', true
      for i of required_images.images
        req_elem = $("#image_" + required_images.images[i])
        if !req_elem.hasClass('active')
          req_elem.addClass 'active'
          $("input#container-" + required_images.images[i]).prop 'checked', true
    return

  $('.container-collection-selector').click ->
    the_element = $(this).attr('data-id')
    if $(this).hasClass('active')
      $(this).removeClass 'active'
      $("input#collection-" + the_element).prop 'checked', false
    else
      $(this).addClass 'active'
      $("input#collection-" + the_element).prop 'checked', true
    return

  $('.container-location-selector').click ->
    the_element = $(this).attr('data-id')
    if $(this).hasClass('active')
      $(this).removeClass 'active'
      $("input#location-" + the_element).prop 'checked', false
    else
      $(this).addClass 'active'
      $("input#location-" + the_element).prop 'checked', true
    return


  $(".container-placement-chooser-auto").change ->
    the_element_id = $(this).attr("data-id")
    $('#placement-' + the_element_id).collapse 'hide'

  $(".container-placement-chooser-man").change ->
    the_element_id = $(this).attr("data-id")
    $('#placement-' + the_element_id).collapse 'show'
