$(() => {

  $('#container-domains-list').DataTable({
    order: [[0, "asc"]],
    pageLength: 50
  });

  $("domains_deployment_id").chosen({
    disable_search_threshold: 10,
    no_results_text: "No projects found for:",
    allow_single_deselect: false
  });

  $("domain_container_service_id").chosen({
    disable_search_threshold: 10,
    no_results_text: "No services found for:",
    allow_single_deselect: true
  });

  $("#domains_deployment_id").change(function () {
    var deployment_id;
    deployment_id = $(this).val();
    if (deployment_id === '') {
      $('#domain_container_service_id').empty()
        .attr('disabled', 'disabled')
        .append('<option>No Services Found</option>')
        .trigger("chosen:updated");
    } else {
      $('#domain_container_service_id').empty()
        .append('<option>...Loading...</option>')
        .trigger("chosen:updated");
      $.ajax({
        url: '/deployments/' + deployment_id + '/services?web_only=true',
        method: 'GET',
        dataType: 'json',
        error: function (xhr, status, error) {
          console.error('Error loading services: ' + status + error);
        },
        success: function (response) {
          var i;
          $('#domain_container_service_id').empty();
          if (response.length === 0) {
            $('#domain_container_service_id').attr('disabled', 'disabled');
            $('#domain_container_service_id').append('<option>No Services Found</option>');
          } else {
            $('#domain_container_service_id').append('<option>Select Service</option>');
            $('#domain_container_service_id').removeAttr('disabled');
          }
          i = 0;
          while (i < response.length) {
            $('#domain_container_service_id').append('<option value="' + response[i]['id'] + '">' + response[i]['label'] + '</option>');
            i++;
          }
          $('#domain_container_service_id').trigger("chosen:updated");
        }
      });
    }
  });

  $("#domain_container_service_id").change(function () {
    var service_id;
    service_id = $(this).val();
    if (service_id === '') {
      $('#domain_ingress_rule_id').empty()
        .attr('disabled', 'disabled')
        .append('<option>No ingress reles Found</option>')
        .trigger("chosen:updated");
    } else {
      $('#domain_ingress_rule_id').empty()
        .append('<option>...Loading...</option>')
        .trigger("chosen:updated");
      $.ajax({
        url: '/container_services/' + service_id + '/ingress',
        method: 'GET',
        dataType: 'json',
        error: function (xhr, status, error) {
          console.error('Error loading ingress rules: ' + status + error);
        },
        success: function (response) {
          var i;
          $('#domain_ingress_rule_id').empty();
          if (response.length === 0) {
            $('#domain_ingress_rule_id').attr('disabled', 'disabled');
            $('#domain_ingress_rule_id').append('<option>No ingress rules Found</option>');
          } else {
            $('#domain_ingress_rule_id').append('<option>Select Ingress Rule</option>');
            $('#domain_ingress_rule_id').removeAttr('disabled');
          }
          i = 0;
          while (i < response.length) {
            $('#domain_ingress_rule_id').append('<option value="' + response[i]['id'] + '">' + response[i]['port'] + ' (' + response[i]['proto'] + ')' + '</option>');
            i++;
          }
          $('#domain_ingress_rule_id').trigger("chosen:updated");
        }
      });
    }
  });

});
