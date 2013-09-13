class PBCoreImporter

  attr_accessor :file, :collection, :url

  def initialize(options={})
    PBCore.config[:date_formats] = ['%m/%d/%Y', '%Y-%m-%d']

    self.collection = Collection.find(options[:collection_id])
    if url.empty? 
    	 raise "File missing or 0 length: #{options[:file]}" unless (File.size?(options[:file]).to_i > 0) 
    	self.file = File.open(options[:file])
    else
    	self.url = options[:url]
    end
  end
  
  def import_url_collection
	pbc_collection = PBCore::V2::Collection.parse(open(url))
	pbc_collection.description_documents.each do |doc|
      sleep(2)
			item_for_omeka_doc(doc).save!
	end
  end

  def import_omeka_description_document
    doc = PBCore::V2::DescriptionDocument.parse(file)
    item_for_omeka_doc(doc).save!
  end

  def import_omeka_collection
    pbc_collection = PBCore::V2::Collection.parse(file)
    pbc_collection.description_documents.each do |doc|
      sleep(2)
			item_for_omeka_doc(doc).save!
    end
  end

  def item_for_omeka_doc(doc)
    item = Item.new
    item.collection        = collection
    item.date_created      = doc.detect_element(:asset_dates, match_value: ['created', nil], value: :date)
    item.identifier        = doc.detect_element(:identifiers)
    item.episode_title     = doc.detect_element(:titles, match_value: 'episode', default_first: false)
    item.series_title      = doc.detect_element(:titles, match_value: 'series', default_first: false)
    item.title             = doc.detect_element(:titles)
    item.tags              = doc.subjects.collect{|s| s.value}.compact
    item.description       = doc.detect_element(:descriptions)
    item.physical_location = doc.detect_element(:coverages, match_value: 'spatial', value: :info, default_first: false).try(:value)
    item.creators          = doc.creators.collect{|c| Person.for_name(c.name.value)}
    item.contributions     = doc.contributors.collect{|c| Contribution.new(person:Person.for_name(c.name.value), role:c.role.value)}
    item.rights            = doc.rights.collect{|r| [r.summary.try(:value), r.link.try(:value), r.embedded.try(:value)].compact.join("\n") }.compact.join("\n")
    item.notes             = doc.detect_element(:annotations, match_value: 'notes', default_first: false)
    item.transcription     = doc.detect_element(:annotations, match_value: 'transcript', default_first: false)

    # process each instance
    doc.instantiations.each do |pbcInstance|
      next if pbcInstance.physical

      instance = item.instances.build
      instance.digital    = true
      instance.format     = pbcInstance.try(:digital).try(:value)
      instance.identifier = pbcInstance.detect_element(:identifiers)
      instance.location   = pbcInstance.location

      if pbcInstance.parts.blank?
        url = pbcInstance.detect_element(:location)
        next unless Utils.is_audio_file?(url)

        audio = AudioFile.new
        instance.audio_files << audio
        item.audio_files << audio
        audio.identifier        = url
        audio.remote_file_url   = url
        audio.format            = instance.format
        audio.size              = pbcInstance.file_size.try(:value).to_i
      else
        pbcInstance.parts.each do |pbcPart|
          url = pbcPart.detect_element(:location)
          next unless Utils.is_audio_file?(url)

          audio = AudioFile.new
          instance.audio_files << audio
          item.audio_files << audio
          audio.identifier        = url
          audio.remote_file_url   = url
          audio.format            = pbcPart.try(:digital).try(:value) || instance.format
          audio.size              = pbcPart.file_size.try(:value).to_i
        end   
      end

      item.instances << instance

    end
    item
  end

end
