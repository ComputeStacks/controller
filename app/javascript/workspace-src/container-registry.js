$(() => {
  if ($("#container-registry-list").length) {
    $("#container-registry-list").load("/container_registry?js=true");
    setInterval((function () {
      return $("#container-registry-list").load("/container_registry?js=true");
    }), 5000);
  }
});

