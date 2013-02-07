require 'csv'
class CsvImport < ActiveRecord::Base

  STATES = ["new", "queued_analyze", "analyzing", "analyzed", "queued_import", "importing", "imported", "error"]

  attr_accessible :file, :mappings_attributes, :commit
  before_save :set_file_name, on: :create
  if Rails.env.test?
    after_save :enqueue_processing, if: :processing_required?
  else
    after_commit :enqueue_processing, if: :processing_required?
  end
  validates_presence_of :file
  mount_uploader :file, ::CsvFileUploader

  has_many :rows, class_name: 'CsvRow'
  has_many :items

  has_many :mappings, order: "position", class_name:'ImportMapping' do
    def [](index)
      conditions(['import_mappings.index = ?', index]).limit(1).first
    end
  end
  accepts_nested_attributes_for :mappings

  attr_accessor :commit

  def state
    STATES[state_index]
  end

  def analyze!
    raise "Invalid state for analysis: #{state}" if %w(new analyzing).include? state
    self.state = "analyzing"
    file.cache!
    CSV.foreach(file.path) do |row|
      if self.headers.present?
        rows.create values: row
      else
        analyze_headers! row
      end
    end
    self.state = "analyzed"
  end

  def import!
    raise "Invalid state for import: #{state}" unless %(queued_import).include? state
    current_mappings = mappings
    self.state = "importing"
    transaction do
      rows.find_each do |csv_row|
        data = csv_row.values
        item = items.build do |item|
          current_mappings.each do |mapping|
            index = mapping.position - 1
            mapping.apply(data[index], item)
          end
        end
        item.save
      end
      self.state = "imported"
    end
  end

  def error!(exception=nil)
    self.error_message = exception.message
    self.backtrace     = exception.backtrace
    self.state         = "error"
  end

  def processing_required?
    state == 'new' || commit.present?
  end

  def process!
    case state
    when "queued_analyze" then analyze!
    when "queued_import"  then import!
    end
  end


  alias_method :mappings_attributes_set, :mappings_attributes=
  def mappings_attributes=(values)
    mappings.delete_all
    self.mappings_attributes_set values
  end

  private

  def state=(state)
    raise "Invalid state: #{state}" unless new_state_index = STATES.index(state.downcase)
    update_attribute :state_index, new_state_index
  end

  def enqueue_processing
    type_of_processing = (commit || 'analyze')
    self.commit = nil
    self.state = "queued_#{type_of_processing}"
    CsvImportWorker.perform_async(id) unless Rails.env.test?
  end

  def set_file_name
    self.file_name = File.basename(file.path)
  end

  def analyze_headers!(headers)
    self.headers = headers
    mappings.delete_all

    headers.each_with_index do |header, index|
      column, type = case header.downcase
      when /identifier/ then ["identifier", "string"]
      when /interviewee/ then ["interviewees[]", "person"]
      when /piece|title/ then ["title", "string"]
      when /date/ then ["date_created", "date"]
      else [make_column_name(header), "*"]
      end

      mappings.create(type:type, column:column) do |mapping|
        mapping.position = index
      end
    end
  end

  def make_column_name(name) 
    "extra.#{name.downcase.gsub(/\W+/,'_')}"
  end

end
