import {Socket} from "phoenix"

// Fetch a socket token, to actually be able to connect:
function fetchSocketToken(onOk, onFail) {
  let page_current_user = document.querySelector("meta[name='bors-current-user']");
  if (page_current_user === null) {
    setTimeout(() => onFail("current user"), 0);
  }
  page_current_user = Number(page_current_user.content);
  let current_token = sessionStorage.getItem("bors-socket-token");
  current_token = current_token === null ? null : JSON.parse(current_token);
  // Refresh the token every half hour.
  let timeout = Date.now() + (1000 * 60 * 30);
  if (current_token === null || current_token.current_user !== page_current_user || current_token.time < timeout) {
    let ajax = new XMLHttpRequest();
    ajax.open("GET", "/auth/socket-token", true);
    ajax.onreadystatechange = function() {
      if (ajax.readyState === XMLHttpRequest.DONE) {
        if (ajax.status === 200) {
          let new_token = JSON.parse(ajax.responseText);
          new_token.time = Date.now();
          if (new_token.current_user !== page_current_user) {
            onFail("ajax current user");
          } else {
            sessionStorage.setItem("bors-socket-token", JSON.stringify(new_token));
            onOk(new_token.token);
          }
        } else {
          onFail("ajax");
        }
      }
    };
    ajax.send();
  } else {
    setTimeout(() => onOk(current_token.token), 0);
  }
}

// Connect to a socket, including the user token fetching:
function connectSocket(onOk, onError) {
  fetchSocketToken(function(token) {
    let socket = new Socket("/socket", {params: {token: token}});
    socket.connect();
    onOk(socket);
  }, onError);
}

// Find project reload dialog element, and connect if it's there.
let reload_template = document.getElementById("js--on-project-ping");
if (reload_template !== null) {
  connectSocket(function(socket) {
    let project_id = Number(reload_template.getAttribute("data-bors-project-id"));
    setupProjectPingChannel(socket, project_id);
  }, function(error) {
    console.log("bors socket error: " + error)
  });
}
// Pop up the project reload dialog.
function popupProjectPingDialog() {
  reload_template.removeAttribute("hidden");
}
// If this is the project page, pop up the reload dialog.
function setupProjectPingChannel(socket, project_id) {
  let channel = socket.channel("project_ping:"+project_id, {});
  channel.join()
    .receive("ok", resp => { console.log("Joined successfully", resp) })
    .receive("error", resp => { console.log("Unable to join", resp) });
  channel.on("new_msg", popupProjectPingDialog);
}
