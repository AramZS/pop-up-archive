class Task < ActiveRecord::Base
  serialize :extras, HstoreCoder

  attr_accessible :name, :extras, :owner_id, :owner_type, :status, :identifier, :type
  belongs_to :owner, polymorphic: true
  belongs_to :storage, class_name: "StorageConfiguration", foreign_key: :storage_id

  CREATED  = 'created'
  WORKING  = 'working'
  FAILED   = 'failed'
  COMPLETE = 'complete'

  scope :incomplete, where('status != ?', COMPLETE)

  # convenient scopes for subclass types
  [:analyze, :copy, :transcribe, :upload].each do |task_subclass|
    scope task_subclass, where('type = ?', "Tasks::#{task_subclass.to_s.titleize}Task")
  end

  # we need to retain the storage used to kick off the process
  before_validation(on: :create) do
    self.extras = {} unless extras
    self.storage_id = owner.storage.id if (!storage_id && owner && owner.storage)
  end

  state_machine :status, initial: :created do

    state :created,  value: CREATED
    state :working,  value: WORKING
    state :failed,   value: FAILED
    state :complete, value: COMPLETE

    event :begin do
      transition all - [:working] => :working
    end

    event :finish do
      transition  all - [:complete] => :complete
    end

    event :failure do
      transition  all - [:failed] => :failed
    end

  end

end
