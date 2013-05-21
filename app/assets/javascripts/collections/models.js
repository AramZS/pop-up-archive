;(function(){
angular.module('Directory.collections.models', ['RailsModel'])
.factory('Collection', ['Model', 'Item', function (Model, Item) {
  var Collection = Model({url:'/api/collections/{{id}}', name: 'collection'});
  var PublicCollection = Model({url:'/api/collections/public', name:'collection'});
  Collection.public = function () {
    return PublicCollection.query.apply(PublicCollection, arguments);
  }

  Collection.prototype.fetchItems = function () {
    var self = this;
    return Item.get({collectionId: this.id}).then(function (items) {
      self.items = items;
      return self;
    });
  }

  Collection.attrAccessible = ['title', 'description', 'itemsVisibleByDefault'];

  return Collection;
}])
.filter('publicCollections', function () {
  var pub = [];
  return buildCollectionFilter(true, pub);
})
.filter('privateCollections', function() {
  var pvt = [];
  return buildCollectionFilter(false, pvt);
})
.filter('notUploads', ['Me', function (Me) {
  var user = {};
  var c = [];
  Me.authenticated(function (currentUser) {
    user = currentUser;
  });
  return function (collections) {
    if (angular.isArray(collections)) {
      c.splice(0, c.length);
      angular.forEach(collections, function (collection, index) {
        if (collection.id != user.uploadsCollectionId) {
          c.push(collection);
        }
      });
      return c;
    } else {
      return collections;
    }
  };
}]);

function buildCollectionFilter(visible, array) {
  return function(collections) {
    if (angular.isArray(collections)) {
      array.splice(0, array.length);
      angular.forEach(collections, function(collection) {
        if (collection.itemsVisibleByDefault == visible) {
          array.push(collection);
        }
      });
      return array
    } else {
      return collections;
    }
  };
}
})();