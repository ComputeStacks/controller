@loadReqChart = ->
  $ ->
    if $('#network_req_chart').length
      remote_url = $('#network_req_chart').attr 'data-resource'
      c3.generate(
        bindto: '#network_req_chart'
        data:
          x: 'dates'
          xFormat: '%Y-%m-%d %H:%M'
          url: remote_url
          mimeType: 'json'
        axis: x:
          type: 'timeseries'
          tick: format: '%H:%M'
        subchart:
          show: true
      )

#loadDeploymentServices = (firstrun)->
#  $ ->
#    if firstrun
#      remote_url = $('#deployment-services').attr 'data-url'
#      remote_url = remote_url + '?a=containers&js=true&firstrun=true'
#    else
#      remote_url = $('#deployment-services').attr 'data-url'
#      remote_url = remote_url + '?a=containers&js=true'
#    $('#deployment-services').load remote_url, ->
#      if firstrun
#        $('.cservice-health-status').each ->
#          status_url = $(this).attr 'data-url'
#          $(this).load status_url

jQuery ->

#  loadDeploymentServices(true)
#
#  setInterval (->
#    loadDeploymentServices(false)
#  ), 5000

#  setInterval (->
#    if $('body').hasClass('screen-active') || $(this).hasClass('always-refresh')
#      loadDeploymentServices(false)
#  ), 5000

  if $('#network_req_chart').length
    loadReqChart()
    setInterval (->
      loadReqChart()
    ), 60000 # 1 minute