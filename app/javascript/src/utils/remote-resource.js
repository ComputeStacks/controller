window.addEventListener('load', (event) => {

  // in-line ajax load (e.g. passwords).
  const inlineRemoteParents = document.querySelectorAll('.inline-remote-resource');
  inlineRemoteParents.forEach(function(item) {
    item.addEventListener(('click'), function(e) {
      parent = $(item).parent();
      $(parent).html('<i class="fa-solid fa-rotate fa-spin"></i>');
      $(parent).load($(this).attr('href'))
      e.preventDefault();
    });
  });

  // full remote resource blocks
  const remoteParents = document.querySelectorAll('.remote-resource');
  remoteParents.forEach(function(item) {
    const remote_url = $(item).attr('data-url');
    $(item).load(remote_url);
    if ($(item).hasClass('refresh')) {
      setInterval((() => $(item).load(remote_url)), 6500);
    }
  });

});

