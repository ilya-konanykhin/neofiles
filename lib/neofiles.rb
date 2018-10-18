require 'neofiles/engine'
require 'aspect_ratio'

module Neofiles
  # Attach Neofiles specific routes in your routes.rb file:
  #
  #   instance_eval &Neofiles.routes_proc
  mattr_accessor :routes_proc
  @@routes_proc = proc do
    scope 'neofiles', module: :neofiles do
      # admin routes
      get  '/admin/file_compact/', to: 'admin#file_compact', as: :neofiles_file_compact
      post '/admin/file_save/', to: 'admin#file_save', as: :neofiles_file_save
      post '/admin/file_remove/', to: 'admin#file_remove', as: :neofiles_file_remove
      post '/admin/file_update/', to: 'admin#file_update', as: :neofiles_file_update

      # admin routes for WYSIWYG editor Redactor.js
      post '/admin/redactor-upload/', to: 'admin#redactor_upload', as: :neofiles_redactor_upload
      get  '/admin/redactor-list/:owner_type/:owner_id/:type', to: 'admin#redactor_list', as: :neofiles_redactor_list

      # web frontend for serving images and other files
      get  '/serve/:id', to: 'files#show', as: :neofiles_file
      get  '/serve-image/:id(/:format(/c:crop)(/q:quality))', to: 'images#show', as: :neofiles_image, constraints: {format: /[1-9]\d*x[1-9]\d*/, crop: /[10]/, quality: /[1-9]\d*/}

      # serve images w/o watermark - path has prefix nowm_ to let Nginx ot other web server not cache these queries,
      # unlike usual /serve-image/:id
      get  '/nowm-serve-image/:id', to: 'images#show', as: :neofiles_image_nowm, defaults: {nowm: true}
    end
  end

  # Calculate image dimensions after resize. Returns [w, h] or nil if some info is lacking (e.g. image passed as ID so
  # no width & height available).
  #
  #   image_file      - Neofiles::Image, ID or Hash
  #   width, height   - max width and height after resize
  #
  def resized_image_dimensions(image_file, width, height, resize_options)
    # dimensions are equal to requested ones if cropping
    return width, height if crop_requested? resize_options

    # otherwise ask ImageMagick - prepare input vars...
    image_file = Neofiles::Image.find image_file if image_file.is_a?(String)
    return nil if image_file.nil?

    if image_file.is_a? Neofiles::Image
      image_file_width = image_file.width
      image_file_height = image_file.height
    elsif image_file.is_a? Hash
      image_file_width = image_file[:width]
      image_file_height = image_file[:height]
    end

    # no input, terminate
    return if image_file_width.blank? || image_file_height.blank?

    # image fits into requested dimensions, no resizing will occur
    return image_file_width, image_file_height if image_file_width <= width && image_file_height <= height

    AspectRatio.resize(image_file_width, image_file_height, width, height).map(&:to_i)

  rescue
    nil
  end

  # Is request params hash contains crop request?
  def crop_requested?(params)
    params[:crop].present? and params[:crop] != '0'
  end

  # Is request params hash contains quality request?
  def quality_requested?(params)
    !!quality_requested(params)
  end

  # The quality value requested, from request params hash.
  def quality_requested(params)
    params[:quality].to_i if params[:quality].present? and params[:quality] != '0'
  end

  # Is current user considered "admin"? "Admin" means the user can fetch images w/o watermarks.
  def is_admin?(context)
    Rails.application.config.neofiles.try(:current_admin).try(:call, context)
  end

  module_function :resized_image_dimensions, :crop_requested?, :quality_requested?, :quality_requested, :is_admin?
end
