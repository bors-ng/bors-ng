var repoID = window.location.pathname.match(/\/\d+\//)[0];
var logTableBody = document.querySelector("#log-table > tbody");
var logsRequestButton = document.querySelector("#log-request");
var requestLogs = function(e) {
  e.preventDefault();
  let lastLogEntryInfo = getLastLogEntryInfo();
  let lowestCrashID = lastLogEntryInfo["crashID"];
  let oldestCrashUpdatedAt = lastLogEntryInfo["crashUpdatedAt"];
  let ajax = new XMLHttpRequest();
  ajax.open("GET", `/repositories${repoID}log_page?crash_id=${lowestCrashID}&crash_updated_at=${decodeURIComponent(oldestCrashUpdatedAt)}`, true);
  ajax.onreadystatechange = function() {
    if (ajax.readyState === XMLHttpRequest.DONE) {
      if (ajax.status === 200) {
        let log_page_info = JSON.parse(ajax.responseText);
        let html = log_page_info["html"];
        if (html && html.length > 0) {
          let dummyTableBody = document.createElement("tbody");
          dummyTableBody.innerHTML = html;
          Array.from(dummyTableBody.children).forEach(entry => {
            let time = entry.querySelector("time");
            prettifyDateTime(time);
            logTableBody.appendChild(entry);
          });
        }
      } else {
        // Failed to retrieve logs
      }
    }
  };
  ajax.send();
  };
logsRequestButton.onclick = requestLogs;

function getLastLogEntryInfo() {
  let lastCrashID = 0;
  let lastCrashUpdatedAt = "";
  Array.from(logTableBody.children).forEach(entry => {
    let id = entry.id;
    if (id.includes("crash")) {
      lastCrashID = entry.dataset.id;
      lastCrashUpdatedAt = entry.dataset.datetime;
    }
    // TODO: get info for batch
  });
  return {crashID: lastCrashID, crashUpdatedAt: lastCrashUpdatedAt};
}

// taken from time-convert.js
// TODO: how to remove code duplication?
function prettifyDateTime(time) {
  const date = new Date(time.innerHTML);
  time.setAttribute("title", date.toUTCString());
  time.innerHTML = date.toLocaleString();
};