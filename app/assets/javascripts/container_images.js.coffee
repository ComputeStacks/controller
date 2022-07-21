jQuery ->

  imageTag = $('#container-image-table').DataTable
    order: [[ 0, "asc" ]]
    pageLength: 25
    deferRender: true
    ajax: '/container_images'
    columns: [
      { data: "name" },
      { data: "owner" },
      { data: "image" },
      { data: "tag" },
      { data: "button_group" }
    ]

  setInterval (->
    imageTag.ajax.reload null, false
  ), 30000
