@loadContainerChart = ->
  $ ->
    if $('#cpu_mem_chart').length
      remote_url = $('#cpu_mem_chart').attr 'data-resource'
      remote_resource = remote_url + '?js=true&a=cpu_mem'
      c3.generate(
        bindto: '#cpu_mem_chart'
        data:
          x: 'dates'
          xFormat: '%Y-%m-%d %H:%M'
          url: remote_resource
          mimeType: 'json'
        axis: x:
          type: 'timeseries'
          tick: format: '%H:%M'
        subchart:
          show: true
      )

jQuery ->

  if $('#cpu_mem_chart').length
    loadContainerChart()
    setInterval (->
      loadContainerChart()
    ), 60000 # 1 minute

  $("select#container_log_container_select").change ->
    container_id = $(this).val()
    new_url = "/containers/" + container_id + "/container_logs"
    window.location = new_url
    return
