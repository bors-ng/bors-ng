const items = document.querySelectorAll(".time-convert");
Array.prototype.forEach.call(items, convertTime);

function convertTime(time) {
    const date = new Date(time.innerHTML);
    time.setAttribute("title", date.toUTCString());
    time.innerHTML = date.toLocaleString();
}

export { convertTime };