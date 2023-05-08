window.addEventListener('load', (event) => {

  const rangeSliders = document.querySelectorAll('.range-slider');

  const sliderVal = document.getElementById('range-slider-val');

  rangeSliders.forEach(function(slider) {

    slider.addEventListener('change', function() {
      sliderVal.innerText = slider.value;
    });

  });



});
