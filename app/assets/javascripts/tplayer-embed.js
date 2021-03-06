/* Pop Up Archive embeddable Transcript Player 
   Copyright 2014 - Pop Up Archive
   Licensed under the AGPL -- see https://github.com/popuparchive/pop-up-archive/blob/master/LICENSE.txt
*/

requirejs.config({
  baseUrl: 'assets'
});

requirejs(['jquery', 'jquery.jplayer', 'tplayer'], function($) {
  var sc = $("script");
  var rootUrl = null;
  $.each(sc, function(idx, tag) {
    console.log(tag);
    if (!tag.src || rootUrl) {
        return;
    }   
    var url = tag.src.match(/^(.+)\/assets\/tplayer-embed\.js\??/);
    console.log(url);
    if (url && url.length && url[1]) {
        rootUrl = url[1];
    }   
  });
  console.log('rootUrl:', rootUrl);
  var loadCss = function(url) {
    var link = document.createElement("link");
    link.type = "text/css";
    link.rel = "stylesheet";
    link.href = url;
    // prepend so that consumer can override our styles
    $("head").prepend(link);
  }
  var cssIsLoaded = function(cssName) {
    for (var i in document.styleSheets) {
      var css = document.styleSheets[i];
      if (!css || !css.href) {
        continue;
      }
      //console.log("css:", css.href);
      if (css.href == rootUrl+'/'+cssName) {
        //console.log('css already loaded:', cssName);
        return true;
      }
    }
    return false;
  };
  // because css is prepended, check in reverse load order
  $.each(['assets/tplayer.css', 'assets/jPlayer.css'], function(idx,cssName) {
    if (!cssIsLoaded(cssName)) {
      loadCss(cssName);
    } 
  }); 
  //console.log("everything loaded");

  var initPlayer = function(conf) {
    $("#pua-tplayer-"+conf.file_id).jPlayer({
      ready: function () {
        $(this).jPlayer("setMedia", {
          title: conf.title,
          oga: conf.ogg,
          mp3: conf.mp3
        });
      },
      loadedmetadata: function() {
        var jplayer = this;
        jplayer.puaTplayer = new PUATPlayer({
          fileId: conf.file_id, 
          jplayer: jplayer,
          play: { start: parseInt(conf.start||0), end: conf.end }
        });
      },
      cssSelectorAncestor: '#jp_container-'+conf.file_id,
      smoothPlayBar: true,
      keyEnabled: true,
      remainingDuration: true,
      toggleDuration: true,
      swfPath: rootUrl+"/assets/Jplayer.swf",
      solution: "html, flash",
      supplied: "oga, mp3"
    });
  };

  // once DOM is ready, find all the <script> tags on the page with
  // the data-main for tplayer-embed, and fire off XHR request to get the needed
  // player data. The transcript+player HTML should already be present; if it isn't,
  // then request and insert it (which is less ideal from an SEO perspective but Will Just Work
  // for playing audio.
  $(document).ready(function() {
    $('script').each(function(idx) {
      var el = $(this);
      if (!el.data('main')) return true; // skip
      if (el.data('main').match(/assets\/tplayer-embed$/)) {
        var fileId = el.data('pua');
        if (!fileId) {
          throw new Error("Missing data-pua attribute on script tag -- cannot embed tplayer");
        }
        // fire XHR for data
        $.ajax(rootUrl+'/tplayer/'+fileId+'.json', {
          dataType: 'jsonp'
        })
        .fail(function(data, stat, jqXHR) {
          console.log("FAIL:", data, stat);
        })
        .done(function(data, stat, jqXHR) {
          console.log("OK:", data, stat);
          // look for HTML container, fetching it if necessary
          var containerId = '#pua-tplayer-'+fileId;
          var container   = $(containerId);
          if (container && container.length) {
            initPlayer(data);
          }
          else {
            // use the oembed service to get the HTML to inject.
            // pass the nojs=1 flag because *we* are the JS.
            $('<div id="pua-tplayer-embed-wrapper-'+fileId+'"></div>').insertAfter(el);
            $.ajax( rootUrl+'/oembed?nojs=1&format=json&url='+rootUrl+'/tplayer/'+fileId, {
              dataType: 'jsonp'
            }) 
            .fail(function(data2, stat2, jqXHR2) {
              console.log("FAIL2:", data2, stat2);
            })
            .done(function(data2, stat, jqXHR2) {
              $('#pua-tplayer-embed-wrapper-'+fileId).html(data2.html);
              initPlayer(data); 
            });
          } // end if container else
        }); // end outer xhr
      } // end data-main=tplayer-embed
    }); // end script.each
  }); // end document.ready

});
