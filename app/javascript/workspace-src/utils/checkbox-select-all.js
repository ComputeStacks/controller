$(() => {

  let $chkboxes, lastChecked;
  $chkboxes = $('input.chkbox-multi');
  lastChecked = null;
  return $chkboxes.click(function(e) {
    var end, start;
    if (!lastChecked) {
      lastChecked = this;
      return;
    }
    if (e.shiftKey) {
      start = $chkboxes.index(this);
      end = $chkboxes.index(lastChecked);
      $chkboxes.slice(Math.min(start, end), Math.max(start, end) + 1).prop('checked', lastChecked.checked);
    }
    lastChecked = this;
  });

});
