import { convertTime } from './time-convert.js';

var pathParts = window.location.pathname.match(/\/\d+\//);

if (pathParts.length > 0) {
  activateRepo(pathParts[0]);
}

function activateRepo(repoID) {
  var logTableBody = document.querySelector("#log-table > tbody");
  var logsRequestButton = document.querySelector("#log-request");
  var requestLogs = function(e) {
    e.preventDefault();
    let lastLogEntryInfo = getLastLogEntryInfo();
    let batchID = lastLogEntryInfo["batchID"];
    let crashID = lastLogEntryInfo["crashID"];
    let updatedAt = lastLogEntryInfo["updatedAt"];
    let ajax = new XMLHttpRequest();
    ajax.open("GET", `/repositories${repoID}log_page?batch_id=${batchID}&crash_id=${crashID}&updated_at=${decodeURIComponent(updatedAt)}`, true);
    ajax.onreadystatechange = function() {
      if (ajax.readyState === XMLHttpRequest.DONE) {
        if (ajax.status === 200) {
          let html = ajax.responseText;
          if (html && html.length > 0) {
            let dummyTableBody = document.createElement("tbody");
            dummyTableBody.innerHTML = html;
            Array.from(dummyTableBody.children).forEach(entry => {
              let time = entry.querySelector("time");
              convertTime(time);
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
    let lastBatchID = -1;
    let lastCrashID = -1;
    let lastUpdatedAt = "";
    Array.from(logTableBody.children).forEach(entry => {
      let id = entry.id;
      if (id.includes("batch")) {
        lastBatchID = entry.dataset.id;
      } else if (id.includes("crash")) {
        lastCrashID = entry.dataset.id;
      }
      lastUpdatedAt = entry.dataset.datetime;
    });
    return {batchID: lastBatchID, crashID: lastCrashID, updatedAt: lastUpdatedAt};
  }
}
