ActiveAdmin.register Collection do
  actions :all, :except => [:edit, :destroy]
  index do
    column :title, sortable: :title do |coll| link_to col.title, superadmin_collection_path(coll) end
    column :default_storage, sortable: :default_storage do |coll| coll.storage.provider end
    column :creator
  end

  filter :title

  show do 
    panel "Collection Details" do
      attributes_table_for collection do
        row("ID") { collection.id }
        row("Title") { collection.title }
        row("Creator") { collection.creator ? (link_to collection.creator.name, superadmin_user_path(collection.creator)) : '(none)' }
        row("Storage") { collection.storage }
        row("Created") { collection.created_at }
        row("Updated") { collection.updated_at }
      end     
    end
    panel "Items" do
      table_for collection.items do|tbl|
        tbl.column("ID") {|item| item.id }
        tbl.column("Title") {|item| link_to item.title, superadmin_item_path(item) }
        tbl.column("Created") {|item| item.created_at }
        tbl.column("Duration") {|item| item.duration }
      end
    end
   
    active_admin_comments
  end

end
