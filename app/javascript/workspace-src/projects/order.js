function setContainerPackage() {

  $('button.container-package-selection').each( (index, element) => {
    let choose_text = $(this).attr('data-choose');
    $(this).removeClass('btn-info');
    $(this).addClass('btn-default');
    $(this).removeAttr('disabled');
    $(this).html(choose_text);
  });

  $('input.container-package-input').each( (i, v) => {
    let selected_btn = 'button#cpackage-btn-' + $(v).attr('data-index') + '-' + $(v).attr('value');
    let selected_text = $(selected_btn).attr('data-selected');
    $(selected_btn).addClass('btn-info');
    $(selected_btn).removeClass('btn-default');
    $(selected_btn).attr('disabled', 'disabled');
    $(selected_btn).html(selected_text);
  });

}

$(document).ready(function() {

  // Location Selection
  $('.container-location-selector').click(function() {
    let the_element = $(this).attr('data-id');
    if ($(this).hasClass('active')) {
      $(this).removeClass('active');
      $("input#location-" + the_element).prop('checked', false);
    } else {
      $(this).addClass('active');
      $("input#location-" + the_element).prop('checked', true);
    }
  });

  $(".container-placement-chooser-auto").change(function() {
    let the_element_id = $(this).attr("data-id");
    return $('#placement-' + the_element_id).collapse('hide');
  });

  $(".container-placement-chooser-man").change(function() {
    let the_element_id = $(this).attr("data-id");
    $('#placement-' + the_element_id).collapse('show');
  });

  // Image Selection
  $('.container-package-selector').click(function() {
    let cid, pid;
    cid = $(this).attr('data-id');
    pid = 'p' + cid;
    $('input#' + pid).val($(this).attr('data-package'));
    $("a[data-id='" + cid + "']").each( (index, e) => {
      return $(e).removeClass('active');
    });
    $(this).addClass('active');
    return false;
  });

  $('.container-image-selector').click(function() {
    var i, req_elem, required_images, the_element;
    the_element = $(this).attr('data-id');
    required_images = $.parseJSON($(this).attr('data-required'));
    if ($(this).hasClass('active')) {
      $(this).removeClass('active');
      $("input#container-" + the_element).prop('checked', false);
    } else {
      $(this).addClass('active');
      $("input#container-" + the_element).prop('checked', true);
      for (i in required_images.images) {
        req_elem = $("#image_" + required_images.images[i]);
        if (!req_elem.hasClass('active')) {
          req_elem.addClass('active');
          $("input#container-" + required_images.images[i]).prop('checked', true);
        }
      }
    }
  });

  // Package Selection
  if ($('.container-package-selection').length) {
    setContainerPackage();
  }

  $('.container-package-selection').click(function() {
    let package_id = $(this).attr('data-package-id');
    let input_element = 'input#p' + $(this).attr('data-i');
    $(input_element).val(package_id);
    setContainerPackage();
  });

});
