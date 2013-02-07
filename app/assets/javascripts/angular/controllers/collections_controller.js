(window.controllers = window.controllers || angular.module('Directory.controllers', []))
.controller('CollectionsCtrl', ['$scope', 'Collection', function CollectionsCtrl($scope, Collection) {
  Collection.query().then(function(data) {
    $scope.collections = data;
  });

  $scope.delete = function(index) {
    var collection = $scope.collections[index];
    collection.deleting = true;
    collection.delete().then(function() {
      $scope.collections.splice(index, 1);
    });
  }
}])
.controller('CollectionCtrl', ['$scope', '$routeParams', 'Collection', function CollectionCtrl($scope, $routeParams, Collection) {
  $scope.collection = Collection.get($routeParams.collectionId);
}])
.controller('CollectionFormCtrl', ['$scope', 'Collection', function CollectionFormCtrl($scope, Collection) {
  $scope.collection = ($scope.collection || new Collection);

  $scope.submit = function() {
    $scope.collection.create().then(function(data) {
      $scope.collection = new Collection;
      $scope.collections.push(data);
    });
  }
}]);

