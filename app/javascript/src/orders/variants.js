window.addEventListener('load', () => {

  const toggleVolumeParamButtons = document.querySelectorAll('.order-image-variant-list-toggle');

  toggleVolumeParamButtons.forEach(function (toggleBtn) {
    toggleBtn.addEventListener('click', function() {
      let elementId = toggleBtn.getAttribute('data-list-id');
      let volumeList = document.getElementById(elementId);
      let currentState = volumeList.style.display;

      if (currentState === 'none') {
        toggleBtn.innerHTML = "[CLOSE]";
        volumeList.style.display = 'block';

      } else {
        toggleBtn.innerHTML = "[MODIFY]";
        volumeList.style.display = 'none';
      }
    });
  });

});
