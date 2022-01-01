$(() => {
  this.inlineRemoteResource = function (id) {
    return $(function () {
      let elem = "#" + id;
      let the_url = $(elem + ' a').attr('href');
      $(elem).html('<i class="fa fa-refresh fa-spin"></i>');
      return $(elem).load(the_url);
    });
  };
});
