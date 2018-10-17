module Neofiles
  class Engine < ::Rails::Engine
    config.autoload_paths << File.expand_path('../..', __FILE__)
    config.neofiles = ActiveSupport::OrderedOptions.new

    # mongo specific settings
    config.neofiles.mongo_files_collection            = 'files.files'
    config.neofiles.mongo_chunks_collection           = 'files.chunks'
    config.neofiles.mongo_temp_chunks_collection      = 'files.temp_chunks'
    config.neofiles.mongo_client                      = 'neofiles'
    config.neofiles.mongo_default_chunk_size          = 4.megabytes
    config.neofiles.mongo_temp_chunks_collection_size = 100.megabytes
    config.neofiles.use_temp_storage                  = false

    # image related settings
    config.neofiles.image_rotate_exif     = true # rotate image, if exif contains orientation info
    config.neofiles.image_clean_exif      = true # clean all exif fields on save
    config.neofiles.image_max_dimensions  = nil  # resize huge originals to meaningful size: [w, h], {width: w, height: h}, wh
    config.neofiles.image_max_crop_width  = 2000 # users can request resizing only up to this width
    config.neofiles.image_max_crop_height = 2000 # users can request resizing only up to this height

    # default watermarker — redefine to set special watermarking logic
    # by default, watermark only images larger than 300x300 with watermark at the bottom center, taken from file
    # /app/assets/images/neofiles/watermark.png
    config.neofiles.watermarker = ->(image, no_watermark: false, watermark_width:, watermark_height:){
      if watermark_width < 300 || watermark_height < 300 || no_watermark
        return image.to_blob
      end

      image.composite(MiniMagick::Image.open(Rails.root.join('app', 'assets', 'images', 'neofiles', 'watermark.png'))) do |c|
        c.gravity 'south'
        c.geometry '200x+0+20'
      end.to_blob
    }
  end
end
