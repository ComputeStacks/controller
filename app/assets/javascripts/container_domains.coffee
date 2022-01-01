jQuery ->

  $('#container-domains-list').DataTable
    order: [[ 0, "asc" ]]
    pageLength: 50

  $("select#domains_deployment_id").chosen
    disable_search_threshold: 10
    no_results_text: "No projects found for:"
    allow_single_deselect: false


  $("select#domain_container_service_id").chosen
    disable_search_threshold: 10
    no_results_text: "No services found for:"
    allow_single_deselect: true

  $("select#domains_deployment_id").change ->
    deployment_id = $(this).val()
    if deployment_id == ''
      $('select#domain_container_service_id').empty()
      $('select#domain_container_service_id').attr 'disabled', 'disabled'
      $('select#domain_container_service_id').append '<option>No Services Found</option>'
      $('select#domain_container_service_id').trigger "chosen:updated"
    else
      $('select#domain_container_service_id').empty()
      $('select#domain_container_service_id').append '<option>...Loading...</option>'
      $('select#domain_container_service_id').trigger "chosen:updated"
      $.ajax
        url: '/deployments/' + deployment_id + '/services?web_only=true'
        method: 'GET'
        dataType: 'json'
        error: (xhr, status, error) ->
          console.error 'Error loading services: ' + status + error
          return
        success: (response) ->
          $('select#domain_container_service_id').empty()
          if response.length == 0
            $('select#domain_container_service_id').attr 'disabled', 'disabled'
            $('select#domain_container_service_id').append '<option>No Services Found</option>'
          else
            $('select#domain_container_service_id').append '<option>Select Service</option>'
            $('select#domain_container_service_id').removeAttr 'disabled'
          i = 0
          while i < response.length
            $('select#domain_container_service_id').append '<option value="' + response[i]['id'] + '">' + response[i]['label'] + '</option>'
            i++
          $('select#domain_container_service_id').trigger "chosen:updated"
          return
      return

  $("select#domain_container_service_id").change ->
    service_id = $(this).val()
    if service_id == ''
      $('select#domain_ingress_rule_id').empty()
      $('select#domain_ingress_rule_id').attr 'disabled', 'disabled'
      $('select#domain_ingress_rule_id').append '<option>No ingress reles Found</option>'
      $('select#domain_ingress_rule_id').trigger "chosen:updated"
    else
      $('select#domain_ingress_rule_id').empty()
      $('select#domain_ingress_rule_id').append '<option>...Loading...</option>'
      $('select#domain_ingress_rule_id').trigger "chosen:updated"
      $.ajax
        url: '/container_services/' + service_id + '/ingress'
        method: 'GET'
        dataType: 'json'
        error: (xhr, status, error) ->
          console.error 'Error loading ingress rules: ' + status + error
          return
        success: (response) ->
          $('select#domain_ingress_rule_id').empty()
          if response.length == 0
            $('select#domain_ingress_rule_id').attr 'disabled', 'disabled'
            $('select#domain_ingress_rule_id').append '<option>No ingress rules Found</option>'
          else
            $('select#domain_ingress_rule_id').append '<option>Select Ingress Rule</option>'
            $('select#domain_ingress_rule_id').removeAttr 'disabled'
          i = 0
          while i < response.length
            $('select#domain_ingress_rule_id').append '<option value="' + response[i]['id'] + '">' + response[i]['port'] + ' (' + response[i]['proto'] + ')' + '</option>'
            i++
          $('select#domain_ingress_rule_id').trigger "chosen:updated"
          return
      return
