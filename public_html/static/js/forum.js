function getSel(el) {
  var st = "";
  if (document.selection != undefined) {
    el.focus();
    var sel = document.selection.createRange();
    st = sel.text;
  } else if (el.selectionStart != undefined) {
    var startPos = el.selectionStart;
    var endPos = el.selectionEnd;
    st = el.value.substring(startPos, endPos);
  }
  return st;
}

function getSelPos(el, out) {
  if (document.selection != undefined) {
    el.focus();
    var sel = document.selection.createRange();
    out.start = sel.startOffset;
    out.end = sel.endOffset;
  } else if (el.selectionStart != undefined) {
    var startPos = el.selectionStart;
    var endPos = el.selectionEnd;
    out.start = startPos;
    out.end = endPos;
  }
}

function put(what) {
  var ta = document.getElementById("ta");
  var spos = {};
  getSelPos(ta, spos);
  var ov = ta.value;
  var nv = ov.substring(0, spos.start) + "[" + what + "]" + getSel(ta) + "[/" + what + "]" + ov.substring(spos.end);
  ta.value = nv;
}

function like(post){
    var id = post.getAttribute("data-post");
    var csrf = post.getAttribute("csrf");
    var i = $(post).find("i.react-emote");
    var span = $(post).find("span.count");
    var n = parseInt(span.text());
    $.post(csrf, function(resp){
        if(resp != 0){
            n += parseInt(resp);
            span.text(n);
        }
    });
}

window.addEventListener("load", () => {
  document.querySelectorAll("time").forEach(date => {
    const dateObject = new Date(date.getAttribute("datetime") + "Z")
    const ago = Date.now() - dateObject;
    const withTime = date.hasAttribute("with-time")
    const relTime = date.hasAttribute("relative-time")
    const parts = [dateObject.toLocaleDateString()]
    if(withTime) parts.push(dateObject.toLocaleTimeString())
    let timeString = parts.join(" ").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    if(relTime && ago < 7 * 86400000) {
      const daysAgo = ((ago / 86400000) | 0);
      const hoursAgo = ((ago / 3600000) | 0);
      const minsAgo = ((ago / 60000) | 0);
      if(ago < 3600000) {
        timeString = "<b><span class='recent'>" + minsAgo + " minute" + (minsAgo == 1 ? "" : "s") + " ago</span></b>";
      } else if(ago < 86400000) {
        timeString = "<b><span class='recent'>" + hoursAgo + " hour" + (hoursAgo == 1 ? "" : "s") + " ago</span></b>";
      } else if(ago < 3 * 86400000) {
        timeString = "<b><span class='recent'>" + daysAgo + " day" + (daysAgo == 1 ? "" : "s") + " ago</span></b>";
      } else {
        timeString = "<b>" + daysAgo + " day" + (daysAgo == 1 ? "" : "s") + " ago</b>";
      }
    }
    date.innerHTML = timeString
  })
})