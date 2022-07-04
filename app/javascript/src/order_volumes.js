window.addEventListener('load', () => {

  const toggleVolumeParamButtons = document.querySelectorAll('.volume-param-toggle');
  // const volParamMountTypeList = document.querySelectorAll('.volume-param-order-select-type');

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

  // volParamMountTypeList.forEach(function(selectList) {
  //   setVolParamWizard(selectList);
  //   selectList.addEventListener('change', function(e) {
  //     setVolParamWizard(selectList);
  //   });
  //
  // });
  //
  // function setVolParamWizard(selectList) {
  //   let volMountKind = selectList.options[selectList.selectedIndex].text;
  //   let cloneType = selectList.getAttribute('data-clone-kind');
  //   let volumeListId = selectList.getAttribute('data-vol-mount-list');
  //   let cloneVolId = selectList.getAttribute('data-clone-vol');
  //   let snapVolId = selectList.getAttribute('data-restore-snap');
  //
  //   console.log(volMountKind);
  //
  //   let volList = document.getElementById(volumeListId);
  //   let cloneVol = document.getElementById(cloneVolId);
  //   let snapVol = document.getElementById(snapVolId);
  //
  //   if (volMountKind === 'Mount') {
  //     volList.style.display = 'block';
  //     cloneVol.style.display = 'none';
  //     snapVol.style.display = 'none';
  //   } else if (volMountKind === 'Clone') {
  //     volList.style.display = 'none';
  //     if (cloneType === 'volume') {
  //       cloneVol.style.display = 'block';
  //       snapVol.style.display = 'none';
  //     } else {
  //       cloneVol.style.display = 'none';
  //       snapVol.style.display = 'block';
  //     }
  //   } else {
  //     volList.style.display = 'none';
  //     cloneVol.style.display = 'none';
  //     snapVol.style.display = 'none';
  //   }
  // }



});
