/* Pop Up Archive embedded transcript/player */

"use strict"

var PUATPlayer = function(opts) {
  // parse opts
  if (!opts.fileId) {
    throw new Error("fileId required");
  }
  if (!opts.jplayer) {
    throw new Error("jplayer required");
  }
  this.fileId  = opts.fileId;
  this.jplayer = opts.jplayer;

  // create waveform
  this.generateWaveform();
  this.el      = $('#jp_container-' + this.fileId);
  this.element = this.el.find('.scrubber canvas')[0];
  this.jp_pbar = this.el.find('.jp-progress');

  if (!opts.play) {
    this.time    = parseInt(this.el.find('.jp-time-holder .jp-current-time').html());
    this.ms      = this.el.find('.jp-time-holder .jp-duration').html().split(':');
    this.duration = parseInt(this.ms[0]*60 + this.ms[1]);
  }

  this.context = this.element.getContext('2d');
  this.mapped  = this.mapToArray(this.wavformData, this.el.width());
  this.draw();
  this.jp_seek_bar = this.el.find('.jp-progress .jp-seek-bar');
  var img = this.element.toDataURL();
  this.jp_seek_bar.css("background", 'url('+img+') no-repeat');
  // redraw the canvas in different color for the progressive play bar
  this.draw('rgb(255, 190, 48)');
  img = this.element.toDataURL();
  this.jp_play_bar = this.el.find('.jp-progress .jp-play-bar');
  this.jp_play_bar.css("background", 'url('+img+') no-repeat');

  // setup
  this.setListeners();
  this.bindEvents();

};

PUATPlayer.prototype = {
  setListeners: function() {
    var self = this;
    $("#jp-reverse-button-"+this.fileId).on('click', function() {
      $(self.jplayer).jPlayer('playHead', 0);
    });
    $('#pua-tplayer-'+this.fileId+'-transcript .pua-tplayer-text').click(function() {
      var clicked = this;
      var offset  = $(clicked).data('offset');
      //console.log('clicked on text with id', clicked.id, offset);
      $(self.jplayer).jPlayer('play', offset);
    });
    $('#pua-tplayer-'+this.fileId+'-transcript .pua-tplayer-text').hover(
      function() { $(this).addClass('hover'); },
      function() { $(this).removeClass('hover'); }
    );
  },

  bindEvents: function() {
    var self = this;
    $(self.jplayer).bind($.jPlayer.event.timeupdate, function(ev) { self.scrollOnPlay(ev) });
    $(self.jplayer).bind($.jPlayer.event.seeking, function(ev) {
      //console.log('seeking');
    });
    $(self.jplayer).bind($.jPlayer.event.seeked, function(ev) { self.scrollOnSeek(ev) });
  },

  scrollOnPlay: function(ev) {
    var self = this;
    var curOffset = Math.floor( ev.jPlayer.status.currentTime );
    // if the current offset matches a text id, select the text
    var target = $('#pua-tplayer-text-'+self.fileId+'-'+curOffset);
    self.scrollToLine(target);
  },

  scrollToLine: function(target) {
    var self = this;
    if (target && target.length && !target.hasClass('selected')) {
      // de-select any currently selected first
      var curSelected = $("#pua-tplayer-"+self.fileId+"-transcript .pua-tplayer-text.selected");
      curSelected.removeClass('selected');
      // select new target
      target.addClass('selected');
      // scroll
      var scrollMath = {};
      scrollMath.rowsBefore = 2;
      scrollMath.lineNum    = parseInt( target.data('idx') );
      var tgtWrap = $("#pua-tplayer-"+self.fileId+"-transcript.scrolling tbody");
      // we want to scroll the sum of the heights of all rows before the current one, less rowsBefore height.
      if (scrollMath.lineNum < scrollMath.rowsBefore) {
        scrollMath.scrollTo = 0;  // already near the top
      }
      else {
        // get the sum of heights for the range of rows.
        // we can't assume that all rows are the same height because lines wrap.
        scrollMath.scrollTo = 0;
        scrollMath.stopper = scrollMath.lineNum - scrollMath.rowsBefore - 1;  // minus one because idx below is zero-based
        if (scrollMath.stopper < 0) scrollMath.stopper = 0;
        var allRows = $("#pua-tplayer-"+self.fileId+"-transcript .pua-tplayer-text");
        allRows.each(function(idx,el) {
          //console.log(idx + ' -> ' + $(el)[0].scrollHeight);
          scrollMath.scrollTo += $(el)[0].scrollHeight;
          if (idx == scrollMath.stopper) return false; // abort loop
        });
      }
      //console.log('scrollMath: ', scrollMath);
      tgtWrap.animate({ scrollTop: scrollMath.scrollTo }, 200);
    }
    //console.log('player timeupdate', curOffset, target, target.length, target.hasClass('selected'));
  },

  scrollOnSeek: function(ev) {
    var self = this;
    var curOffset = Math.floor( ev.jPlayer.status.currentTime );
    // find nearest target
    var target = self.findNearestLine(curOffset);
    self.scrollToLine(target);
  },

  findNearestLine: function(offset) {
    // look for a target matching offset, working backward till we find one.
    var self = this;
    var target = $('#pua-tplayer-text-'+self.fileId+'-'+offset);
    while (!target.length) {
      offset--;
      target = $('#pua-tplayer-text-'+self.fileId+'-'+offset);
      if (offset <= 0) { break; }
    }
    return target;
  },

  waveformData: [],

  waveform: function() {
    return this.waveformData;
  },

  generateWaveform: function() {
    this.waveformData.length = 0;
    var l = 0;
    var segments = parseInt(Math.random() * 1000 + 1000);

    for (var i=0; i < segments; i++) {
      l = this.waveformData[i] = Math.max(Math.round(Math.random() * 10) + 2, Math.min(Math.round(Math.random() * -20) + 50, Math.round(l + (Math.random() * 25 - 12.5))));
    }   
  },

  canvasWidth: function() {
    return this.jp_pbar.width();
  },

  canvasHeight: function() {
    return this.jp_pbar.height();
  },

  barTop: function(size, height) {
    return Math.round((50 - size) * (height / 50) * 0.5);
  },

  barHeight: function(size, height) {
    return Math.round(size * (height / 50));
  },

  mapToArray: function(waveform, size) {
    var currentPixel = 0;
    var currentChunk = 0;
    var waveform = this.waveformData;
    var chunksPerPixel = waveform.length / size;
    var chunkStart, chunkEnd, sum, j;
    var array = [];
    while (currentPixel < size) {
      chunkStart = Math.ceil(currentChunk);
      currentChunk += chunksPerPixel;
      chunkEnd = Math.floor(currentChunk);

      sum = 0;
      for (j = chunkStart; j <= chunkEnd; j += 1) {
        sum += waveform[j];
      }

      array[currentPixel] = sum / (chunkEnd - chunkStart + 1);
      currentPixel += 1;
    }
    return array;
  },

  draw: function(color) {
    var height = this.canvasHeight();
    var width  = this.mapped.length;
    this.element.width = width;
    this.element.height = height;
    var scrubberEnd = Math.round(width * this.time / this.duration) || 0;
    console.log('scrubberEnd=', scrubberEnd, 'width=', width, 'height=', height);
    this.context.clearRect(0, 0, width + 200, height + 200);
    if (color) {
      this.context.fillStyle = color;
    }
    else {
      this.context.fillStyle = 'rgb(255, 190, 48)';
    }
    for (var i = 0; i < width; i++) {
      if (i == scrubberEnd && !color) {
        this.context.fillStyle = "rgb(187, 187, 187)";
      }
      this.context.fillRect(i, this.barTop(this.mapped[i], height), 1, this.barHeight(this.mapped[i], height));
    }
  }

};

