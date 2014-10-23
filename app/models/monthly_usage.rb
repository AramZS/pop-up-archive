class MonthlyUsage < ActiveRecord::Base

  belongs_to :entity, :polymorphic => true
  attr_accessible :entity, :entity_id, :entity_type, :month, :year, :use, :value, :yearmonth

  PREMIUM_TRANSCRIPTS = 'premium transcripts'
  BASIC_TRANSCRIPTS   = 'basic transcripts'

  before_save :set_yearmonth

  def set_yearmonth
    self.yearmonth = sprintf("%d-%02d", year, month)
  end

end
