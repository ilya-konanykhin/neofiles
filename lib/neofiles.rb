# encoding: UTF-8
require "neofiles/engine"

module Neofiles
  # maybe config
  mattr_accessor :watermarker
  @@watermarker = ->(image, preferred_width = nil){
    image = MiniMagick::Image.read image unless image.is_a? MiniMagick::Image

    image.composite(MiniMagick::Image.open(Rails.root.join("app", "assets", "images", "neofiles-watermark.png"))) do |c|
      c.gravity 'south'
      preferred_width = [200, preferred_width].max if preferred_width > 0
      c.geometry "#{preferred_width}x+0+20"
    end.to_blob
  }

  mattr_accessor :routes_proc
  @@routes_proc = proc do
    scope 'neofiles', module: :neofiles do
      get  '/admin/file_compact/', to: 'admin#file_compact', as: 'neofiles_file_compact'
      post '/admin/file_save/', to: 'admin#file_save', as: 'neofiles_file_save'
      post '/admin/file_remove/', to: 'admin#file_remove', as: 'neofiles_file_remove'

      post '/admin/redactor-upload/', to: 'admin#redactor_upload', as: 'neofiles_redactor_upload'
      get  '/admin/redactor-list/:owner_type/:owner_id/:type', to: 'admin#redactor_list', as: 'neofiles_redactor_list'

      get  '/serve/:id', to: 'files#show', as: 'neofiles_file'
      get  '/serve-image/:id(/:format(/c:crop)(/q:quality))', to: 'images#show', as: 'neofiles_image', constraints: {format: /[1-9]\d*x[1-9]\d*/, crop: /[10]/, quality: /[1-9]\d*/}

      # получаем полную картинку без водяного знака
      # путь начинается с nowm, чтобы nginx не кэшировал его, наравне с /serve*
      get  '/nowm-serve-image/:id', to: 'images#show', as: 'neofiles_image_nowm', defaults: {nowm: true}
    end
  end
end

require_relative "../app/models/neofiles"
