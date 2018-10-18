module Neofiles
  class Engine < ::Rails::Engine
    config.autoload_paths << File.expand_path('../..', __FILE__)
    config.neofiles = ActiveSupport::OrderedOptions.new

    # mongo specific settings
    config.neofiles.mongo_files_collection    = 'files.files'
    config.neofiles.mongo_chunks_collection   = 'files.chunks'
    config.neofiles.mongo_client              = 'neofiles'
    config.neofiles.mongo_default_chunk_size  = 4.megabytes

    # image related settings
    config.neofiles.image_rotate_exif     = true # rotate image, if exif contains orientation info
    config.neofiles.image_clean_exif      = true # clean all exif fields on save
    config.neofiles.image_max_dimensions  = nil  # resize huge originals to meaningful size: [w, h], {width: w, height: h}, wh
    config.neofiles.image_max_crop_width  = 2000 # users can request resizing only up to this width
    config.neofiles.image_max_crop_height = 2000 # users can request resizing only up to this height

    config.neofiles.album_append_create_side = :right # picture when added is displayed on the right

    # default storage
    config.neofiles.write_data_stores = 'mongo'
    config.neofiles.read_data_stores  = 'mongo'

    # default watermarker — redefine to set special watermarking logic
    # by default, watermark only images larger than 300x300 with watermark at the bottom center, taken from file
    # /app/assets/images/neofiles/watermark.png
    config.neofiles.watermarker = ->(convert, _image, width, height) {
      return if width < 300 || height < 300

      wm_path = Rails.root.join('app', 'assets', 'images', 'neofiles', 'watermark.png')
      return unless ::File.exists?(wm_path)

      convert << wm_path
      convert.gravity 'south'
      convert.geometry '200x+0+20'
      convert.composite
    }
  end
end
