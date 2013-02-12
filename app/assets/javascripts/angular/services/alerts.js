angular.module('Directory.alerts', [])
.factory('Alert', ['$timeout', '$rootScope', function ($timeout, $rootScope) {
  var alerts = [];

  function schedulePeriodicUpdate (alert) {
      alert.$timeout = $timeout(function () {
      alert.sync(alert).then(function (arg) {
        if (!(alert.done || alert.path || alert.progress == 100)){
          schedulePeriodicUpdate(alert);
        } else {
          $rootScope.loading(false);
        }
        return arg;
      });
    }, 500);
  }

  function Alert(data) {
    data = (data || {});
    this.status   = data.status;
    this.message  = data.message;
    this.path     = data.path;
    this.done     = data.done;
    this.progress = data.progress;
    this.sync     = data.sync;
  }

  Alert.prototype = {
    add: function () {
      alerts.push(this);
      this.startSync();
    },

    startSync: function (sync) {
      var promise;
      this.sync = (sync || this.sync);
      if (typeof this.sync == 'function') {
        promise = this.sync(this);
        if (promise && typeof promise.then == 'function') {
          $rootScope.loading(true);
          schedulePeriodicUpdate(this);
        }
      }
    },
    
    dismiss: function () {
      if (this.$timeout && typeof this.$timeout.cancel == 'function'){
        this.$timeout.cancel();
      }
      alerts.splice(alerts.indexOf(this), 1);
    }
  }

  Alert.add = function(alert) {
    var newAlert = new Alert(alert);
    alert.add();
    return alert;
  }

  Alert.getAlerts = function() {
    return alerts;
  }

  return Alert;
}]);