@inlineRemoteResource = (id)->
  $ ->
    elem = "#" + id
    the_url = $(elem + ' a').attr('href')
    $(elem).html '<i class="fa fa-refresh fa-spin"></i>'
    $(elem).load the_url

jQuery ->

  Cookies.set 'browser.timezone', jstz.determine().name(),
    expires: 365
    path: '/'

  $(":range").rangeinput
    progress: true
    keyboard: false
    css:
      input: "range" # class name for the generated text input field
      slider: "cslider" # class name for rangeinput
      progress: "cprogress" # class name for progress bar
      handle: "handle" # class name for drag handle

#  checkPageFocus = ->
#    elem = document.getElementsByTagName('BODY')[0]
#    if document.hasFocus()
#      elem.className = 'has-nav screen-active'
#    else
#      elem.className = 'has-nav'
#    return
#
#  setInterval checkPageFocus, 200

  $("input.save-btn").click ->
    $(this).val($(this).attr('data-locale'))
    $(this).attr "disabled", "disabled"
    $("form#" + $(this).attr('data-form')).submit()

  $('.chosen-select-standard').chosen
    allow_single_deselect: true
    no_results_text: 'None found.'
    disable_search_threshold: 5

  $('.remote-resource').each ->
    remote_url = $(this).attr 'data-url'
    the_elem = $(this)
    $(this).load remote_url
    if $(this).hasClass('refresh')
      setInterval (->
        the_elem.load remote_url
      ), 6500


  $chkboxes = $('input.chkbox-multi')
  lastChecked = null
  $chkboxes.click (e) ->
    if !lastChecked
      lastChecked = this
      return
    if e.shiftKey
      start = $chkboxes.index(this)
      end = $chkboxes.index(lastChecked)
      $chkboxes.slice(Math.min(start, end), Math.max(start, end) + 1).prop 'checked', lastChecked.checked
    lastChecked = this
    return

  # Date Range and DateTime Range Pickers

  if $('input.datefilter').length
    $('input.datefilter').daterangepicker
      autoUpdateInput: false
      locale:
        format: 'll'
        cancelLabel: 'Clear'

    $('input.datefilter').on 'apply.daterangepicker', (ev, picker) ->
      $(this).val picker.startDate.format('lll') + ' - ' + picker.endDate.format('lll')
      return

    $('input.datefilter').on 'cancel.daterangepicker', (ev, picker) ->
      $(this).val ''
      return

  if $('input.datetimefilter').length
    $('input.datetimefilter').daterangepicker
      autoUpdateInput: false
      timePicker: true
      startDate: moment().startOf('hour').subtract(7, 'days')
      endDate: moment().startOf('hour')
      locale:
        cancelLabel: 'Clear'
        format: 'lll'

    $('input.datetimefilter').on 'apply.daterangepicker', (ev, picker) ->
      $(this).val picker.startDate.format('lll') + ' - ' + picker.endDate.format('lll')
      return

    $('input.datetimefilter').on 'cancel.daterangepicker', (ev, picker) ->
      $(this).val ''
      return
