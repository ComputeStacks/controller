jQuery ->

  addEventListener 'trix-file-accept', (event) ->
    alert "File uploads not allowed."
    event.preventDefault()
    return