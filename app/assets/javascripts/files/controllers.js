angular.module('Directory.files.controllers', ['fileDropzone', 'Directory.csvImports.models', 'Directory.alerts'])
.controller('FilesCtrl', ['$scope', '$http', 'CsvImport', '$timeout', 'Alert', '$modal', '$routeParams', 'Collection', 'Loader', 'Item', function ($scope, $http, CsvImport, $timeout, Alert, $modal, $routeParams, Collection, Loader, Item) {

  $scope.files = [];

  function uploadCSV(file) {
    var alert = new Alert();

    alert.status = "Uploading";
    alert.progress = 1;
    alert.message = file.name;
    alert.add();

    var fData = new FormData();
    fData.append('csv_import[file]', file);

    $http({
      method: 'POST',
      url: '/api/csv_imports',
      data: fData,
      headers: { "Content-Type": undefined },
      transformRequest: angular.identity
    }).success(function(data, status, headers, config) {
      var csvImport = new CsvImport({id:data.id});
      alert.progress = 25;
      alert.status = "Waiting";
      alert.startSync(csvImport.alertSync());
    });
  }

  $scope.uploadAudioFiles = function(newFiles) {

    newFiles = newFiles || [];

    Loader(Collection.query(), $scope);

    $scope.item = new Item({collectionId:$routeParams.collectionId, title:'', audioFiles:newFiles});

    if (newFiles.length == 1)
      $scope.item.title = newFiles[0].name;

    var modal = $modal({template: '/assets/items/upload.html', show: true, backdrop: 'static', scope: $scope});
  }

  $scope.setFiles = function(element) {
    $scope.$apply(function($scope) {
      angular.forEach(element[0].files, function (file) {
        $scope.item.audioFiles.push(file);
      });
    });
  };

  $scope.submit = function() {

    console.log('submit', $scope.item);
    var item = $scope.item;
    var audioFiles = item.audioFiles;
    item.audioFiles = [];

    item.create().then(function () {

      angular.forEach(audioFiles, function (file) {


        var alert = new Alert();

        alert.status = "Uploading";
        alert.progress = 1;
        alert.message = file.name;
        alert.add();

        item.addAudioFile(file).then(function(data) {
          $scope.addMessage({
            'type': 'success',
            'title': 'Congratulations!',
            'content': '"' + file.name + '" upload completed. <a data-dismiss="alert" data-target=":parent" ng-href="' + item.link() + '">View and edit the new item!</a>'
          });

          alert.progress = 100;
          alert.status = "Uploaded";

        }, function(data){
          console.log('fileUploaded: addAudioFile: reject', data, item);
          $scope.addMessage({
            'type': 'error',
            'title': 'Oops...',
            'content': '"' + file.name + '" upload failed. Hmmm... try again?'
          });

          alert.progress = 100;
          alert.status = "Error";

        });

      });

    });

    $scope.dismiss();

  };

  $scope.$watch('files', function(files) {

    //new files!
    var newFiles = [];

    var newFile;
    while (newFile = files.pop()) {
      if (newFile.name.match(/csv$/i)) {
        uploadCSV(newFile);
      } else {
        newFiles.push(newFile);
      }
    }

    if (newFiles.length > 0) {
      console.log('new files added', newFiles);
      $scope.uploadAudioFiles(newFiles);
    }

  });

}]);
