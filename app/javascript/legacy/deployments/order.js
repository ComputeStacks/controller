/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/main/docs/suggestions.md
 */
const setContainerPackage = function() {

  $('button.container-package-selection').each(function() {
    const choose_text = $(this).attr('data-choose');
    $(this).removeClass('btn-info');
    $(this).addClass('btn-default');
    $(this).removeAttr('disabled');
    return $(this).html(choose_text);
  });

  return $('input.container-package-input').each(function(i,v) {
    const selected_btn = 'button#cpackage-btn-' + $(v).attr('data-index') + '-' + $(v).attr('value');
    const selected_text = $(selected_btn).attr('data-selected');
    $(selected_btn).addClass('btn-info');
    $(selected_btn).removeClass('btn-default');
    $(selected_btn).attr('disabled', 'disabled');
    return $(selected_btn).html(selected_text);
  });
};

const setImageVariant = function() {

  $('button.image-variant-selector').each(function() {
    const choose_text = $(this).attr('data-choose');
    $(this).removeClass('btn-info');
    $(this).addClass('btn-default');
    $(this).removeAttr('disabled');
    return $(this).html(choose_text);
  });

  return $('input.image-variant-input').each(function(i,v) {
    const selected_btn = 'button#image-variant-btn-' + $(v).attr('data-image') + '-' + $(v).attr('value');
    const selected_text = $(selected_btn).attr('data-selected');
    const version_label_field = "span#image-variant-label-" + $(v).attr('data-image');
    $(version_label_field).html($(selected_btn).attr('data-label'));
    $(selected_btn).addClass('btn-info');
    $(selected_btn).removeClass('btn-default');
    $(selected_btn).attr('disabled', 'disabled');
    return $(selected_btn).html(selected_text);
  });
};

const selectContainerAddons = function() {

  $('button.container-addon-selection').each(function() {
    const choose_text = $(this).attr('data-choose');
    $(this).removeClass('btn-info');
    $(this).addClass('btn-default');
    return $(this).html(choose_text);
  });

  return $('input.container-addon-checkbox').each(function(i,v) {
    const selected_btn = 'button#cs-addon-btn-' + $(v).attr('data-index') + '-' + $(v).attr('value');
    const selected_text = $(selected_btn).attr('data-selected');
    if ($(v).attr("checked")) {
      $(selected_btn).addClass('btn-info');
      $(selected_btn).removeClass('btn-default');
      return $(selected_btn).html(selected_text);
    }
  });
};

jQuery(function() {

  if ($('.image-variant-selector').length) {
    setImageVariant();

    $('.image-variant-selector').click(function() {
      const input_element = "input#image-" + $(this).attr('data-image') + "-variant";
      $(input_element).val($(this).attr('data-variant'));
      setImageVariant();
    });
  }

  if ($('.container-addon-selection').length) {
    selectContainerAddons();

    $('.container-addon-selection').click(function() {
      const addon_id = $(this).attr('data-addon');
      const image_variant_id = $(this).attr('data-i');
      const input_element = 'input#addon-checkbox-' + image_variant_id + '-' + addon_id;
      if ($(input_element).attr("checked")) {
        $(input_element).removeAttr("checked");
      } else {
        $(input_element).attr("checked", "checked");
      }
      selectContainerAddons();
    });
  }

  if ($('.container-package-selection').length) {
    setContainerPackage();

    return $('.container-package-selection').click(function() {
      const package_id = $(this).attr('data-package-id');
      const input_element = 'input#p' + $(this).attr('data-i');
      $(input_element).val(package_id);
      setContainerPackage();
    });
  }
});
