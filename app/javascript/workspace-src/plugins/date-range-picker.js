$(document).ready(function() {

  if ($('input.datefilter').length) {
    $('input.datefilter').daterangepicker({
      autoUpdateInput: false,
      locale: {
        format: 'll',
        cancelLabel: 'Clear'
      }
    });
    $('input.datefilter').on('apply.daterangepicker', function(ev, picker) {
      $(this).val(picker.startDate.format('lll') + ' - ' + picker.endDate.format('lll'));
    });
    $('input.datefilter').on('cancel.daterangepicker', function(ev, picker) {
      $(this).val('');
    });
  }
  if ($('input.datetimefilter').length) {
    $('input.datetimefilter').daterangepicker({
      autoUpdateInput: false,
      timePicker: true,
      startDate: moment().startOf('hour').subtract(7, 'days'),
      endDate: moment().startOf('hour'),
      locale: {
        cancelLabel: 'Clear',
        format: 'lll'
      }
    });
    $('input.datetimefilter').on('apply.daterangepicker', function(ev, picker) {
      $(this).val(picker.startDate.format('lll') + ' - ' + picker.endDate.format('lll'));
    });
    return $('input.datetimefilter').on('cancel.daterangepicker', function(ev, picker) {
      $(this).val('');
    });
  }

});
