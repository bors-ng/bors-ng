var setClass = function(toggler, menu, opened) {
  menu.setAttribute("aria-hidden", opened ? "false" : "true");
  toggler.setAttribute("aria-expanded", opened ? "true" : "false");
  if (opened) {
    menu.className = "drop-down-menu drop-down-menu--open";
  } else {
    menu.className = "drop-down-menu";
  }
}

var items = document.querySelectorAll(".drop-down-menu--toggler");
Array.prototype.forEach.call(items, function(toggler) {
  var menu = document.querySelector(toggler.getAttribute("href"));
  var opened = false;
  toggler.setAttribute("aria-controls", menu.id);
  menu.setAttribute("role", "menu");
  setClass(toggler, menu, opened);
  toggler.addEventListener('click', function(e) {
    e.preventDefault();
    e.stopPropagation();
    opened = !opened;
    setClass(toggler, menu, opened);
  });
  document.addEventListener('keydown', function(e) {
    if (!opened) return;
    if (e.keyCode === 27) {
      e.preventDefault();
      e.stopPropagation();
      opened = false;
      setClass(toggler, menu, opened);
    }
  });
  document.addEventListener('click', function(e) {
    if (!opened) return;
    var target = e.target;
    if (target !== menu && !menu.contains(target)) {
      e.preventDefault();
      e.stopPropagation();
      opened = false;
      setClass(toggler, menu, opened);
    }
  });
});
