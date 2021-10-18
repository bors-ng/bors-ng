const items = document.querySelectorAll("td.expand-row");
Array.prototype.forEach.call(items, convertExpandRow);

window.addEventListener("resize", function() {
    const items = document.querySelectorAll("td.expand-row");
    Array.prototype.forEach.call(items, convertExpandRow);
    convertIndicator();
});

window.addEventListener("popstate", convertIndicator);
window.addEventListener("DOMContentLoaded", convertIndicator);

function convertIndicator() {
    var h = Array.prototype.slice.call(document.querySelectorAll("[data-exp-hash]"));
    var l = h.length;
    for (var i = 0; i < l; ++i) {
        h[i].classList.remove("exp-indicator-open");
        h[i].classList.add("exp-indicator-close");
        h[i].setAttribute("aria-expanded", "false");
    }
    if (window.location.hash) {
        h = document.querySelector("[data-exp-hash=\"" + window.location.hash + "\"]");
        if (h && h.hash === window.location.hash) {
            h.classList.add("exp-indicator-open");
            h.classList.remove("exp-indicator-close");
            h.setAttribute("aria-expanded", "true");
        }
    }
}

function getNewID() {
    let fullID;
    do {
        if (!window.borsExpNewID) {
            window.borsExpNewID = 0;
        }
        window.borsExpNewID += 1;
        fullID = "row-" + window.borsExpNewID.toString();
    } while (document.getElementById(fullID));
    return fullID;
}

function convertExpandRow(td) {
    if (td.borsExp) {
        return;
    }
    var row = td.parentElement;
    if (!row.id) {
        row.id = getNewID();
    }
    td.classList.add("fill-link");
    let item;
    if (item = doExpandRow(td)) {
        const a = document.createElement("a");
        a.href = item;
        a.hash = item;
        a.setAttribute("data-exp-hash", item);
        a.addEventListener("click", function(e) {
            if (window.location.hash === this.hash && window.history && window.history.state && window.history.state.borsExp) {
                window.history.back();
                e.preventDefault();
            } else if (window.location.hash !== this.hash) {
                window.location = this.hash;
                window.history.replaceState({borsExp: true}, window.title);
                e.preventDefault();
            }
            convertIndicator();
        });
        while (item = td.firstChild) {
            td.removeChild(item);
            a.appendChild(item);
        }
        td.appendChild(a);
    }
}

function doExpandRow(td) {
    const row = td.parentElement;
    const table = row.parentElement.parentElement;
    const headRow = table.querySelector("thead tr[role=\"row\"]");
    const headItems = Array.prototype.slice.call(headRow.children);
    const colSpan = row.children.length;
    const items = Array.prototype.slice.call(row.children);
    const l = items.length;
    const borsExp = document.createElement("tr");
    borsExp.className = "exp";
    const borsExpInternal = document.createElement("td");
    borsExp.appendChild(borsExpInternal);
    borsExpInternal.setAttribute("colspan", l);
    const borsExpDl = document.createElement("dl");
    borsExpInternal.appendChild(borsExpDl);
    let foundOne = false;
    for (var i = 0; i !== l; ++i) {
        if (items[i].scrollHeight === 0) {
            foundOne = true;
            const dt = document.createElement("dt");
            dt.appendChild(document.createTextNode(headItems[i].innerText));
            const dd = document.createElement("dd");
            dd.appendChild(document.createTextNode(items[i].innerText));
            borsExpDl.appendChild(dt)
            borsExpDl.appendChild(dd);
        }
    }
    if (foundOne) {
        row.parentElement.insertBefore(borsExp, row.nextElementSibling);
        td.borsExp = borsExp;
        borsExp.id = "exp-" + row.id;
        return "#" + borsExp.id;
    } else {
        return false;
    }
}

export { convertExpandRow };