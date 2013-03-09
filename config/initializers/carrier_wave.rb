CarrierWave.configure do |config|
  config.root = Rails.root.join('tmp')
  config.cache_dir = 'carrierwave'

  config.storage        = :fog
  config.fog_directory  = ENV['UPLOAD_S3_BUCKET']
  config.fog_public     = false

  config.fog_credentials = {
    :provider               => 'AWS',       
    :aws_access_key_id      => ENV['UPLOAD_S3_ACCESS_KEY_ID'],       
    :aws_secret_access_key  => ENV['UPLOAD_S3_ACCESS_KEY']
  }


  if Rails.env.test? or Rails.env.cucumber?
    config.storage = :file
    config.enable_processing = false
  end
end
