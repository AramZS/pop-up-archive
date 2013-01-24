class Geolocation < ActiveRecord::Base
  attr_accessible :name

  before_save :generate_slug, on: :create
  has_many :items

  geocoded_by :name

  after_validation :geocode, if: :name_changed?

  def self.for_name(string)
    find_by_slug slugify string or create name: string
  end

  private

  def generate_slug
    self.slug = self.class.slugify name
  end

  def self.slugify(string)
    string.downcase.gsub(/\W/,'')
  end
end
