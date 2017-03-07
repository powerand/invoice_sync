var tbl_content;
function reload_data(){
  var xhr = new XMLHttpRequest();
  xhr.open('GET', document.location.href, true);
  xhr.setRequestHeader('X-RMXHR', '1');
  xhr.overrideMimeType('text/plain');
  indicator.classList.add('read');
  xhr.send();
  xhr.onreadystatechange = function() {
    if (xhr.readyState != 4) return;
    if (xhr.status == 200) {
      localStorage.setItem(document.location.pathname + '_scroll_top', tbl_content.scrollTop);
      document.open();
      document.write(xhr.responseText);
      document.close();
      setTimeout(function(){ tbl_content.scrollTop = localStorage.getItem(document.location.pathname + '_scroll_top'); }, 0);
      indicator.classList.remove('read');
      indicator.classList.add('update');
      setTimeout(function(){ indicator.classList.remove('update'); }, 100);
      return true;
    } else if(xhr.status == 204) {
      indicator.classList.remove('read');
    } else {
      indicator.classList.remove('read');
      indicator.classList.add('error');
      setTimeout(function(){ indicator.classList.remove('error'); }, 100);
      console.error(xhr.status + ': ' + xhr.statusText);
    }
    setTimeout(reload_data, 2000);
  }
}
document.addEventListener("DOMContentLoaded", function(){
  var main_table = document.getElementById('main_table'),
    head_table = document.getElementById('head_table'),
    indicator = document.getElementById('indicator');
  tbl_content = document.getElementsByClassName('tbl-content')[0];
  Array.prototype.forEach.call(document.getElementsByClassName('switch_to'), function(switch_to) {
    switch_to.onclick = function() {
      if(this.classList.contains('current')) return true;
      this.textContent = '⌛';
      localStorage.setItem(document.getElementsByClassName('switch_to current')[0].attributes['page'].value, document.location.pathname + document.location.search + document.location.hash);
      document.location.href = localStorage.getItem(switch_to.attributes['page'].value) || this.attributes['page'].value;
    }
  });
});
window.addEventListener('beforeunload', function(){
  localStorage.setItem(document.location.pathname + '_scroll_top', tbl_content.scrollTop);
});