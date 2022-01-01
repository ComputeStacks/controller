jQuery ->
  $.ajaxSetup cache: false

  if $("#dash-ticket-list").length
    dash_tickets_list_url = $("#dash-ticket-list").attr('data-url') + "?js=true"

    $("#dash-ticket-list").load dash_tickets_list_url

    if $("#is_dev").length
      enable_dash_tickets_refresh = false
    else
      enable_dash_tickets_refresh = true

    if enable_dash_tickets_refresh
      setInterval (->
        $("#dash-ticket-list").load dash_tickets_list_url, ->
      ), 20000