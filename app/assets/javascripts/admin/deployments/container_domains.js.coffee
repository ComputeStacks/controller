jQuery ->

  $("select#deployment_container_domain_user_id").chosen
    disable_search_threshold: 10
    no_results_text: "No users found for:"
    allow_single_deselect: false


  $("select#deployment_container_domain_container_service_id").chosen
    disable_search_threshold: 10
    no_results_text: "No services found for:"
    allow_single_deselect: true

  $("select#deployment_container_domain_user_id").change ->
    user_id = $(this).val()
    $('select#deployment_container_domain_container_service_id').empty()
    $('select#deployment_container_domain_container_service_id').append '<option>...Loading...</option>'
    $('select#deployment_container_domain_container_service_id').trigger "chosen:updated"
    $.ajax
      url: '/admin/users/' + user_id + '/container_services'
      method: 'GET'
      dataType: 'json'
      error: (xhr, status, error) ->
        console.error 'Error loading services: ' + status + error
        return
      success: (response) ->
        $('select#deployment_container_domain_container_service_id').empty()
        if response.length == 0
          $('select#deployment_container_domain_container_service_id').attr 'disabled', 'disabled'
          $('select#deployment_container_domain_container_service_id').append '<option>No Services Found</option>'
        else
          $('select#deployment_container_domain_container_service_id').append '<option>Select Service</option>'
          $('select#deployment_container_domain_container_service_id').removeAttr 'disabled'
        i = 0
        while i < response.length
          $('select#deployment_container_domain_container_service_id').append '<option value="' + response[i]['id'] + '">' + response[i]['name'] + '</option>'
          i++
        $('select#deployment_container_domain_container_service_id').trigger "chosen:updated"
        return
    return

