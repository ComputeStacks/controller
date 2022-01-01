jQuery ->
  $('#admin-search-form').focus ->
    $(this).attr('placeholder', '')

  $('#admin-search-form').blur ->
    $(this).attr('placeholder', $(this).attr('data-placeholder'))
