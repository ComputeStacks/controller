import Trix from "trix"

document.addEventListener("trix-before-initialize", () => {
  // Change Trix.config if you need
})

window.addEventListener('trix-file-accept', function(event) {
  alert("File uploads not allowed.");
  event.preventDefault();
});

