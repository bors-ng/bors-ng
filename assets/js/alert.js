var items = document.querySelectorAll(".js--closable");
var closeButtonClick = function(e) {
  e.preventDefault();
  this.parentNode.setAttribute("hidden", "hidden");
};
Array.prototype.forEach.call(items, function(closable) {
  var closeButton = document.createElement("button");
  closeButton.className = "close-button";
  closeButton.innerHTML = "&times;";
  closeButton.onclick = closeButtonClick;
  closable.appendChild(closeButton);
});
