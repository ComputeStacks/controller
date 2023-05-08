import Sortable from 'sortablejs';

window.addEventListener('load', () => {

  const el = document.getElementById('imageVariantList');
  if (el !== null) {
    const sortable = Sortable.create(el, {
      handle: ".sort-handle",
      onChange: function() {
        document.getElementById("updateImageVariantPosBtn").style.display = 'block';
      }
    });
  }

});
