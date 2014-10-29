ActiveAdmin.register Task do
  actions :index, :show
  menu false
  index do
    column :type do |t| link_to t.type, superadmin_task_path(t) end
    column :created_at
    column :status
    column :owner
    column :identifier
  end

  filter :status
  filter :owner_type
  filter :type

  show do 
    panel "Task Details" do
      attributes_table_for task do
        row("ID") { task.id }
        row("Type") { task.type }
        row("Status") { task.status }
        row("Owner") { task.owner }
        row("Identifier") { task.identifier }
        row("Extras") do |task| 
          attributes_table_for task.extras do  
            task.extras.keys.each do |e| 
              row(e) { task.extras[e] } 
            end 
          end 
        end 
        row("Created") { task.created_at }
        row("Updated") { task.updated_at }
      end     
    end
 
    active_admin_comments
  end

end
