jQuery ->
  $("ul#admin-user-tab li a").click (e) ->
      e.preventDefault()
      $(this).tab "show"
  $('ul#admin-user-tab li a[href="#overview"]').tab('show')

  $('#user-group-list').DataTable
    "order": [[ 0, "desc" ]]
    "pageLength": 25