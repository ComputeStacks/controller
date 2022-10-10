window.addEventListener('load', () => {

  const toggleVolumeParamButtons = document.querySelectorAll('.volume-param-toggle');

  toggleVolumeParamButtons.forEach(function (toggleBtn) {
    toggleBtn.addEventListener('click', function() {
      let elementId = toggleBtn.getAttribute('data-list-id');
      let volumeList = document.getElementById(elementId);
      let currentState = volumeList.style.display;

      if (currentState === 'none') {
        toggleBtn.innerHTML = "[HIDE]";
        volumeList.style.display = 'block';

      } else {
        toggleBtn.innerHTML = "[SHOW]";
        volumeList.style.display = 'none';
      }
    });
  });

});
