var repoID = window.location.pathname.match(/\/\d+\//)[0];
var logTableBody = document.querySelector("#log-table > tbody");
var logsRequestButton = document.querySelector("#log-request");
var requestLogs = function(e) {
  e.preventDefault();
  let lastLogEntryInfo = getLastLogEntryInfo();
  let bID = lastLogEntryInfo["batchID"];
  let bAt = lastLogEntryInfo["batchUpdatedAt"];
  let cID = lastLogEntryInfo["crashID"];
  let cAt = lastLogEntryInfo["crashUpdatedAt"];
  let ajax = new XMLHttpRequest();
  ajax.open("GET", `/repositories${repoID}log_page?batch_id=${bID}&batch_updated_at=${decodeURIComponent(bAt)}&crash_id=${cID}&crash_updated_at=${decodeURIComponent(cAt)}`, true);
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
  let lastBatchID = 0;
  let lastBatchUpdatedAt = "";
  let lastCrashID = 0;
  let lastCrashUpdatedAt = "";
  Array.from(logTableBody.children).forEach(entry => {
    let id = entry.id;
    if (id.includes("batch")) {
      lastBatchID = entry.dataset.id;
      lastBatchUpdatedAt = entry.dataset.datetime;
    } else if (id.includes("crash")) {
      lastCrashID = entry.dataset.id;
      lastCrashUpdatedAt = entry.dataset.datetime;
    }
  });
  return {batchID: lastBatchID, batchUpdatedAt: lastBatchUpdatedAt, crashID: lastCrashID, crashUpdatedAt: lastCrashUpdatedAt};
}

// taken from time-convert.js
// TODO: how to remove code duplication?
function prettifyDateTime(time) {
  const date = new Date(time.innerHTML);
  time.setAttribute("title", date.toUTCString());
  time.innerHTML = date.toLocaleString();
};