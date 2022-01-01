jQuery ->
  $("form#api-credentials-generate").submit ->
    waiting = $("button#api-credentials-generate-btn").attr('data-locale') + '...'
    $("button#api-credentials-generate-btn").html(waiting).attr("disabled", "disabled")
