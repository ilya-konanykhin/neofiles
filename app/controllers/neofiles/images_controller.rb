require 'png_quantizator'

# Special controller for serving images from the database via single action #show.
#
class Neofiles::ImagesController < ActionController::Metal

  class NotAdminException < Exception; end

  include ActionController::DataStreaming
  include ActionController::RackDelegation
  include Neofiles::NotFound

  if defined?(Devise)
    include ActionController::Helpers
    include Devise::Controllers::Helpers
  end

  CROP_MAX_WIDTH = Rails.application.config.neofiles.image_max_crop_width
  CROP_MAX_HEIGHT = Rails.application.config.neofiles.image_max_crop_height

  # Request parameters:
  #
  #   format  - resize image to no more than that size, example: '100x200'
  #   crop    - if '1' and params[:format] is present, then cut image sides if its aspect ratio differs from
  #             params[:format] (otherwise image aspect ration will be preserved)
  #   quality - output quality, integer from 1 till 100 for JPEG input, default is 75
  #             for PNG input any value less than 75 triggers lossless compression using pngquant library
  #   nowm    - force returned image to not contain watermark - user must be admin or 403 Forbidden response is returned
  #             @see #admin_or_die (also this removes the default quality to let admins download image originals)
  #
  # Maximum allowed format dimensions are set via Rails.application.config.neofiles.image_max_crop_width/height.
  #
  # Watermark is added automatically from /assets/images/neofiles/watermark.png or via proc
  # Rails.application.config.neofiles.watermarker if present.
  #
  def show
    # get image
    image_file = Neofiles::Image.find params[:id]

    # prepare headers
    data = image_file.data
    options = {
        filename: CGI::escape(image_file.filename),
        type: image_file.content_type || 'image/jpeg',
        disposition: 'inline',
    }
    quality = [[Neofiles::quality_requested(params), 100].min, 1].max if Neofiles::quality_requested?(params)
    quality ||= 75 unless nowm?(image_file)

    image = MiniMagick::Image.read(data)

    if params[:format].present?
      width, height = params[:format].split('x').map(&:to_i)
      raise Mongoid::Errors::DocumentNotFound unless width.between?(1, CROP_MAX_WIDTH) and height.between?(1, CROP_MAX_HEIGHT)
    end

    crop_requested            = Neofiles.crop_requested? params
    resizing                  = width && height
    need_resize_without_crop  = resizing && (image_file.width > width || image_file.height > height)

    image.combine_options('convert') do |convert|
      resize_image convert, width, height, crop_requested, need_resize_without_crop if resizing

      unless nowm?(image_file)
        wm_width, wm_height = Neofiles::resized_image_dimensions image_file, width, height, params
        add_watermark convert, image, wm_width, wm_height if wm_width && wm_height
      end

      compress_image convert, quality if quality || resizing
    end

    # use pngquant when quality is less than 75
    ::PngQuantizator::Image.new(image.path).quantize! if options[:type] == 'image/png' && quality && quality < 75

    data = image.to_blob

    # stream image headers & bytes
    send_file_headers! options
    headers['Content-Length'] = data.length.to_s
    self.status = 200
    self.response_body = data

  rescue NotAdminException
    self.response_body = I18n.t 'neofiles.403_access_denied'
    self.content_type = 'text/plain; charset=utf-8'
    self.status = 403
  ensure
    image.destroy! #delete mini_magick tempfile
  end



  private

  # Are we serving without watermark? If yes and user is not admin raise special exception.
  def nowm?(image_file)
    image_file.no_wm? || (params[:nowm] == true && admin_or_die)
  end

  # Assert the user logged in is admin. @see Neofiles.is_admin?
  def admin_or_die
    if Neofiles.is_admin? self
      true
    else
      raise NotAdminException
    end
  end

  # Fill convert command pipe with resize commands
  def resize_image(convert, width, height, crop_requested, need_resize_without_crop)
    if crop_requested
      convert.resize "#{width}x#{height}^"
      convert.gravity 'center'
      convert.extent "#{width}x#{height}"
    elsif need_resize_without_crop
      convert.resize "#{width}x#{height}"
    end
  end

  # Fill convert command pipe with compression commands for JPEG and PNG
  # More information: https://www.smashingmagazine.com/2015/06/efficient-image-resizing-with-imagemagick/
  def compress_image(convert, quality)
    convert.quality "#{quality}" if quality
    convert << '-unsharp' << '0.25x0.25+8+0.065'
    convert << '-dither' << 'None'
    #convert << '-posterize' << '136' # posterize slows down imagamagick extremely in some env due to buggy libgomp1
    convert << '-define' << 'jpeg:fancy-upsampling=off'
    convert << '-define' << 'png:compression-filter=5'
    convert << '-define' << 'png:compression-level=9'
    convert << '-define' << 'png:compression-strategy=1'
    convert << '-define' << 'png:exclude-chunk=all'
    convert << '-interlace' << 'none'
    convert << '-colorspace' << 'sRGB'
    convert.strip
  end

  # Add watermarks command to a command pipe, if watermarker is present
  def add_watermark(convert, image, width, height)
    Rails.application.config.neofiles.watermarker.try :call, convert, image, width, height
  end

end