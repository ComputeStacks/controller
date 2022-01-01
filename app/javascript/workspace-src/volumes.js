$(() => {

  $('#volume-list').DataTable({
    "order": [[5, "desc"]],
    "pageLength": 50
  });

  $("select#volume_deployment_id").chosen({
    disable_search_threshold: 10,
    no_results_text: "No projects found for:",
    allow_single_deselect: false
  });

  $("select#volume_container_service_id").chosen({
    disable_search_threshold: 10,
    no_results_text: "No services found for:",
    allow_single_deselect: true
  });


  $("select#volume_deployment_id").change( (element) => {
    let deployment_id = $(element).val();
    if (deployment_id === '') {
      $('select#volume_container_service_id').empty();
      $('select#volume_container_service_id').attr('disabled', 'disabled');
      $('select#volume_container_service_id').append('<option>No Services Found</option>');
      return $('select#volume_container_service_id').trigger("chosen:updated");
    } else {
      $('select#volume_container_service_id').empty();
      $('select#volume_container_service_id').append('<option>...Loading...</option>');
      $('select#volume_container_service_id').trigger("chosen:updated");
      $.ajax({
        url: '/deployments/' + deployment_id + '/services',
        method: 'GET',
        dataType: 'json',
        error: function(xhr, status, error) {
          console.error('Error loading services: ' + status + error);
        },
        success: function(response) {
          let i;
          $('select#volume_container_service_id').empty();
          if (response.length === 0) {
            $('select#volume_container_service_id').attr('disabled', 'disabled');
            $('select#volume_container_service_id').append('<option>No Services Found</option>');
          } else {
            $('select#volume_container_service_id').append('<option>Select Service</option>');
            $('select#volume_container_service_id').removeAttr('disabled');
          }
          i = 0;
          while (i < response.length) {
            $('select#volume_container_service_id').append('<option value="' + response[i]['id'] + '">' + response[i]['label'] + '</option>');
            i++;
          }
          $('select#volume_container_service_id').trigger("chosen:updated");
        }
      });
    }
  });

  $("#volumeCreateBackup").on("hidden.bs.modal", () => {
    $("input#backupName").val("");
  });

});
