module Neofiles
  class Engine < ::Rails::Engine
    config.autoload_paths << File.expand_path('../..', __FILE__)
    config.neofiles = ActiveSupport::OrderedOptions.new

    # default watermarker
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
