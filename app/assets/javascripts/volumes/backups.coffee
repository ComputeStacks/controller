jQuery ->

  $("#volumeCreateBackup").on "hidden.bs.modal", ->
    $("input#backupName").val ""
    return