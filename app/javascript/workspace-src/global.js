import Cookies from 'js-cookie'
import jstz from 'jstz';

$(() => {
// $(document).ready(function() {

  Cookies.set('browser.timezone', jstz.determine().name(), {
    expires: 365,
    path: '/'
  });

  $(".app-flash").each((index, element) => {
    if ($(element).hasClass('alert-success') || $(element).hasClass('alert-info')) {
      $(element).delay(9000).fadeOut('slow');
    }
  });

  $("input.save-btn").click((el) => {
    $(el).val($(el).attr('data-locale'));
    $(el).attr("disabled", "disabled");
    $("form#" + $(el).attr('data-form')).submit();
  });


});
