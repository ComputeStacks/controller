jQuery ->
  $('#products-packages-table').DataTable
    "order": [[ 0, "desc" ]]
    "pageLength": 50
  $('#products-table').DataTable
    "order": [[ 0, "desc" ]]
    "pageLength": 50
