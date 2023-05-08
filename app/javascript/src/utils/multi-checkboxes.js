window.addEventListener('load', (event) => {

  const $chkboxes = $('input.chkbox-multi');
  let lastChecked = null;
  $chkboxes.click(function(e) {
    if (!lastChecked) {
      lastChecked = this;
      return;
    }
    if (e.shiftKey) {
      const start = $chkboxes.index(this);
      const end = $chkboxes.index(lastChecked);
      $chkboxes.slice(Math.min(start, end), Math.max(start, end) + 1).prop('checked', lastChecked.checked);
    }
    lastChecked = this;
  });

});
