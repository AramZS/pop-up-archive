angular.module('Directory.items.controllers', ['Directory.loader', 'Directory.user', 'Directory.items.models', 'Directory.entities.models', 'Directory.people.models'])
.controller('ItemsCtrl', [ '$scope', 'Item', 'Loader', 'Me', function ItemsCtrl($scope, Item, Loader, Me) {
  Me.authenticated(function (data) {
    if ($scope.collectionId) {
      $scope.items = Loader.page(Item.query(), 'Items');
    }
  });

  $scope.startUpload = function() {
    var newFiles = [];
    $scope.$emit('filesAdded', newFiles);
  }

}])
.controller('ItemCtrl', ['$scope', 'Item', 'Loader', 'Me', '$routeParams', 'Collection', 'Entity', function ItemCtrl($scope, Item, Loader, Me, $routeParams, Collection, Entity) {

  $scope.canEdit = false;

  if ($routeParams.id) {
    Loader.page(Item.get({collectionId:$routeParams.collectionId, id: $routeParams.id}), Collection.get({id:$routeParams.collectionId}), Collection.query(), 'Item-v2/'+$routeParams.id, $scope).then(function () {
      angular.forEach($scope.collections, function (collection) {
        if (collection.id == $scope.item.collectionId) {
          $scope.canEdit = true;
        }
      });
    });
  }

  $scope.deleteEntity = function(entity) {
    var e = new Entity(entity);
    e.itemId = $scope.item.id;
    e.deleting = true;
    e.delete().then(function() {
      $scope.item.entities.splice($scope.item.entities.indexOf(entity), 1);
    });
  }

  $scope.confirmEntity = function(entity) {
    // console.log('confirmEntity', entity);
    entity.itemId = $scope.item.id;
    entity.isConfirmed = true;
    var entity = new Entity(entity);
    entity.update();
  }

}])
.controller('ItemFormCtrl', ['$scope', '$routeParams', 'Schema', 'Item', 'Contribution', function ($scope, $routeParams, Schema, Item, Contribution) {

  $scope.item = {};
  $scope.itemTags = [];

  if ($scope.$parent.item) {
    angular.copy($scope.$parent.item, $scope.item);
    angular.forEach($scope.item.tags, function(v,k){ this.push({id:v, text:v}); }, $scope.itemTags);
  }

  $scope.fields = Schema.columns;

  $scope.tagSelect = {
    placeholder: 'Tags...',
    width: '220px',
    tags:[],
    initSelection: function (element, callback) { 
      callback($scope.itemTags);
    }
  };

  $scope.roleSelect = {
    placeholder:'Role...',
    width: '160px'
  };

  $scope.deleteContribution = function(contribution) {
    contribution._delete = true;
  }

  $scope.peopleSelect = {
    placeholder: 'Name...',
    width: '240px',
    minimumInputLength: 2,
    quietMillis: 100,
    formatSelection: function (person) { return person.name; },
    formatResult: function (result, container, query, escapeMarkup) { 
      var markup=[];
      window.Select2.util.markMatch(result.name, query.term, markup, escapeMarkup);
      return markup.join("");
    },
    createSearchChoice: function (term, data) {
      if ($(data).filter(function() {
        return this.name.toUpperCase().localeCompare(term.toUpperCase()) === 0;
      }).length === 0) {
        return { id: 'new', name: term };
      }
    },
    initSelection: function (element, callback) {
      var scope = angular.element(element).scope();
      callback(scope.contribution.person);
    },
    ajax: {
      url: '/api/collections/' + $routeParams.collectionId + '/people',
      data: function (term, page) { return { q: term }; },
      results: function (data, page) { return { results: data }; }
    }
  }

  $scope.$parent.$watch('item', function (is) {
    if (is && $scope.item != is) {
      angular.copy(is, $scope.item);
      $scope.itemTags = [];
      angular.forEach($scope.item.tags, function(v,k){ this.push({id:v, text:v}); }, $scope.itemTags);
    }
  });

  $scope.submit = function () {

    var cleanTags = [];
    angular.forEach($scope.itemTags, function(v,k){ this.push(v.id); }, cleanTags);
    $scope.item.tags = cleanTags;
    
    if ($scope.item.id) {
      $scope.item.update().then(function (data) {
        $scope.item.updateContributions();
        angular.copy($scope.item, $scope.$parent.item);
        // $scope.close();
      });
    } else {
      $scope.item.create().then(function (data) {
        if (angular.isFunction($scope.itemAdded)) {
          $scope.itemAdded($scope.item);
        }
        $scope.close();
      });
    }
  }

}]);
