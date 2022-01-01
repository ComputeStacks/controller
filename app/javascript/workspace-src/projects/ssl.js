$(() => {

  $("select#ssl_deployment_id").change( (element) => {
    let deployment_id = $(element).val();
    if (deployment_id === '') {
      $('select#ssl_container_service_id').empty();
      $('select#ssl_container_service_id').attr('disabled', 'disabled');
      $('select#ssl_container_service_id').append('<option>No Services Found</option>');
      return $('select#ssl_container_service_id').trigger("chosen:updated");
    } else {
      $('select#ssl_container_service_id').empty();
      $('select#ssl_container_service_id').append('<option>...Loading...</option>');
      $('select#ssl_container_service_id').trigger("chosen:updated");
      $.ajax({
        url: '/deployments/' + deployment_id + '/services?web_only=true',
        method: 'GET',
        dataType: 'json',
        error: function(xhr, status, error) {
          console.error('Error loading services: ' + status + error);
        },
        success: function(response) {
          let i;
          $('select#ssl_container_service_id').empty();
          if (response.length === 0) {
            $('select#ssl_container_service_id').attr('disabled', 'disabled');
            $('select#ssl_container_service_id').append('<option>No Services Found</option>');
          } else {
            $('select#ssl_container_service_id').append('<option>Select Service</option>');
            $('select#ssl_container_service_id').removeAttr('disabled');
          }
          i = 0;
          while (i < response.length) {
            $('select#ssl_container_service_id').append('<option value="' + response[i]['id'] + '">' + response[i]['label'] + '</option>');
            i++;
          }
          $('select#ssl_container_service_id').trigger("chosen:updated");
        }
      });
    }
  });

});
