jQuery ->

  $('#sub-usage-table').DataTable
    'order': [[ 1, "desc" ]]
    "pageLength": 25

  $('select#admin-subscription-filter-by-user').on 'change', ->
    full_path = $('select#admin-subscription-filter-by-user').attr('data-url')
    window.location = full_path + '/user/' + @value

