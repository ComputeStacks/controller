$(() =>
  $('.remote-resource').each( (index, element) => {
    let remote_url = $(element).attr('data-url');
    $(element).load(remote_url);
    if ( $(element).hasClass(('refresh')) ) {
      setInterval(() => {
        $(element).load(remote_url);
      }, 6500)
    }
  })
);
