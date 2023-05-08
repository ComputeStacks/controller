/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/main/docs/suggestions.md
 */
jQuery(function() {

  // order
  $('.container-package-selector').click(function() {
    const cid = $(this).attr('data-id');
    const pid = 'p' + cid;
    $('input#' + pid).val($(this).attr('data-package'));
    $("a[data-id='" + cid + "']").each(function() {
      return $(this).removeClass('active');
    });
    $(this).addClass('active');
    return false;
  });

  // Prevent de-selection of image when changing variant
  $('select.order-variant-selector').click(function(e) {
    const cid = $(this).attr('data-id');
    const pid = "#image_" + cid;
    if ($(pid).hasClass('active')) {
      return e.stopPropagation();
    }
  });

  // Selecting a variant should select the image.
  $('select.order-variant-selector').change(function() {
    const cid = $(this).attr('data-id');
    const pid = "#image_" + cid;
    const el = document.querySelector(pid);
    if (!$(pid).hasClass('active')) {
      const newEvent = new Event("click");
      return el.dispatchEvent(newEvent);
    }
  });

  $('.container-image-selector').click(function() {
    const the_element = $(this).attr('data-id');
    const required_images = $.parseJSON($(this).attr('data-required'));
    if ($(this).hasClass('active')) {
      $(this).removeClass('active');
      $("input#container-" + the_element).prop('checked', false);
    } else {
      $(this).addClass('active');
      $("input#container-" + the_element).prop('checked', true);
      for (var i in required_images.images) {
        var req_elem = $("#image_" + required_images.images[i]);
        if (!req_elem.hasClass('active')) {
          req_elem.addClass('active');
          $("input#container-" + required_images.images[i]).prop('checked', true);
        }
      }
    }
  });

  $('.container-collection-selector').click(function() {
    const the_element = $(this).attr('data-id');
    if ($(this).hasClass('active')) {
      $(this).removeClass('active');
      $("input#collection-" + the_element).prop('checked', false);
    } else {
      $(this).addClass('active');
      $("input#collection-" + the_element).prop('checked', true);
    }
  });

  $('.container-location-selector').click(function() {
    const the_element = $(this).attr('data-id');
    if ($(this).hasClass('active')) {
      $(this).removeClass('active');
      $("input#location-" + the_element).prop('checked', false);
    } else {
      $(this).addClass('active');
      $("input#location-" + the_element).prop('checked', true);
    }
  });


  $(".container-placement-chooser-auto").change(function() {
    const the_element_id = $(this).attr("data-id");
    $('#placement-' + the_element_id).collapse('hide');
  });

  return $(".container-placement-chooser-man").change(function() {
    const the_element_id = $(this).attr("data-id");
    $('#placement-' + the_element_id).collapse('show');
  });
});
