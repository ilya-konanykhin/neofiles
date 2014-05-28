# encoding: UTF-8
module Neofiles
  class Engine < ::Rails::Engine
    # isolate_namespace Neofiles
    config.autoload_paths << File.expand_path("../..", __FILE__)
    config.neofiles = ActiveSupport::OrderedOptions.new

    # default watermarker
    config.neofiles.watermarker = ->(image){
      image = MiniMagick::Image.read image unless image.is_a? MiniMagick::Image

      image.composite(MiniMagick::Image.open(Rails.root.join("app", "assets", "images", "neofiles-watermark.png"))) do |c|
        c.gravity 'south'
        c.geometry "200x+0+20"
      end.to_blob
    }
  end
end
