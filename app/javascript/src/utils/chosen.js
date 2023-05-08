import Chosen from "chosen-js"

window.addEventListener('load', (event) => {

  $('.chosen-select-standard').chosen({
    allow_single_deselect: true,
    no_results_text: 'None found.',
    disable_search_threshold: 5
  });

});
