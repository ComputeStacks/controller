jQuery ->
  $("form#new-payment-form").submit ->
    $("button#payment-new-btn").html("Please Wait...").attr("disabled", "disabled")

  $("a#braintree_validation").click ->
      window.open $(this).attr('href'), 'bt', 'status=0,toolbar=0,width=550,height=450'
      false