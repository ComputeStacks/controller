jQuery ->
  if $("#container-registry-list").length
    registry_list_url = "/container_registry?js=true"
    $("#container-registry-list").load registry_list_url
    setInterval (->
      $("#container-registry-list").load registry_list_url
    ), 5000