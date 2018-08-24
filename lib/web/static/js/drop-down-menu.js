var backdrop = document.createElement("div");
backdrop.className = "drop-down-menu-backdrop";
document.getElementsByTagName("body")[0].appendChild(backdrop);

var setClass = function(toggler, menu, opened) {
  var update_hist = window.history.pushState && window.history.replaceState && menu.id;
  menu.setAttribute("aria-hidden", opened ? "false" : "true");
  toggler.setAttribute("aria-expanded", opened ? "true" : "false");
  if (opened) {
    menu.className = "drop-down-menu drop-down-menu--open";
    backdrop.className = "drop-down-menu-backdrop drop-down-menu-backdrop--active";
    if (update_hist && window.location.hash !== ('#' + menu.id)) {
      window.history.pushState({"menu": menu.id}, "", window.location.pathname + '#' + menu.id);
    }
  } else {
    menu.className = "drop-down-menu";
    backdrop.className = "drop-down-menu-backdrop";
    if (update_hist && window.location.hash === ('#' + menu.id)) {
      if (window.history.state && window.history.state.menu === menu.id) {
        window.history.back();
      } else {
        window.location.hash = "";
      }
    }
  }
};

var firstVisibleSibling = function(el) {
  while (el && !el.offsetHeight) {
    el = el.nextElementSibling;
  }
  return el;
};

var lastVisibleSibling = function(el) {
  while (el && !el.offsetHeight) {
    el = el.previousElementSibling;
  }
  return el;
};

var firstVisibleChild = function(el) {
  return firstVisibleSibling(el.firstElementChild);
};

var lastVisibleChild = function(el) {
    return lastVisibleSibling(el.lastElementChild);
};

var items = document.querySelectorAll(".drop-down-menu--toggler");
Array.prototype.forEach.call(items, function(toggler) {
  var hash = toggler.getAttribute("href");
  var menu = document.querySelector(hash);
  var opened = window.location.hash === hash;
  toggler.setAttribute("aria-controls", menu.id);
  menu.setAttribute("role", "menu");
  setClass(toggler, menu, opened);
  toggler.addEventListener('click', function(e) {
    e.preventDefault();
    e.stopPropagation();
    opened = !opened;
    setClass(toggler, menu, opened);
  });
  if (menu.id) {
      window.addEventListener('popstate', function(e) {
          opened = window.location.hash === hash;
          setClass(toggler, menu, opened);
      });
  }

  document.addEventListener('keydown', function(e) {
    if (!opened) return;
    var k = e.key.toLowerCase();
    if (k === "escape") {
      e.preventDefault();
      e.stopPropagation();
      opened = false;
      setClass(toggler, menu, opened);
      toggler.focus();
    } else if (k === "arrowdown") {
      var current = document.querySelector(":focus");
      if (!current || current.parentElement !== menu) {
        firstVisibleChild(menu).focus();
      } else {
        (firstVisibleSibling(current.nextElementSibling) || firstVisibleChild(menu)).focus();
      }
    } else if (k === "arrowup") {
        var current = document.querySelector(":focus");
        if (!current || current.parentElement !== menu) {
            lastVisibleChild(menu).focus();
        } else {
          (lastVisibleSibling(current.previousElementSibling) || lastVisibleChild(menu)).focus();
        }
    }
  });
  document.addEventListener('focusin', function(e) {
    if (!opened) return;
    if (e.target !== toggler && e.target !== menu && e.target.parentNode !== menu) {
      firstVisibleChild(menu).focus();
      e.preventDefault();
    } else if (e.target === toggler) {
      lastVisibleChild(menu).focus();
      e.preventDefault();
    }
  });
  backdrop.addEventListener('click', function(e) {
    if (!opened) return;
    opened = false;
    setClass(toggler, menu, false);
  });
});
