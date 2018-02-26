const items = document.querySelectorAll(".time-convert");
Array.prototype.forEach.call(items, function(time) {
    const date = new Date(time.innerHTML);
    time.setAttribute("title", date.toUTCString());
    time.innerHTML = date.toLocaleString();
});
