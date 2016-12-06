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
  #   quality - output JPEG quality, integer from 1 till 100 (forces JPEG output, otherwise image type is preserved)
  #   nowm    - force returned image to not contain watermark - user must be admin or 403 Forbidden response is returned
  #             @see #admin_or_die
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

    # is resizing needed?
    watermark_image, watermark_width, watermark_height = data, image_file.width, image_file.height
    if params[:format].present?

      width, height = params[:format].split('x').map(&:to_i)
      watermark_width, watermark_height = width, height
      raise Mongoid::Errors::DocumentNotFound unless width.between?(1, CROP_MAX_WIDTH) and height.between?(1, CROP_MAX_HEIGHT)

      quality = [[Neofiles::quality_requested(params), 100].min, 1].max if Neofiles::quality_requested?(params)
      setting_quality = quality && options[:type] == 'image/jpeg'

      image = MiniMagick::Image.read(data)

      if Neofiles.crop_requested? params
        # construct ImageMagick call:
        # 1) resize to WxH, allow the result to be bigger on one side
        # 2) allign resized to center
        # 3) cut the extending parts
        # 4) set quality if requested
        image.combine_options do |c|
          c.resize "#{width}x#{height}^"
          c.gravity 'center'
          c.extent "#{width}x#{height}"
          c.quality "#{quality}" if setting_quality
        end
      else
        # no cropping so just resize to fit in WxH, one side can be smaller than requested
        if image_file.width > width || image_file.height > height
          image.combine_options do |c|
            c.resize "#{width}x#{height}"
            c.quality "#{quality}" if setting_quality
          end
        else
          setting_quality = false
          watermark_width, watermark_height = image_file.width, image_file.height
        end
      end

      # quality requested, but we didn't have a chance to set it before -> forcibly resave as JPEG
      if quality && !setting_quality
        image.format 'jpeg'
        image.quality quality.to_s
      end

      # get image bytes and stuff
      data = image.to_blob
      watermark_image = image
      options[:type] = image.mime_type
    end

    watermark_image = MiniMagick::Image.read watermark_image unless watermark_image.is_a? MiniMagick::Image

    # set watermark
    data = Rails.application.config.neofiles.watermarker.(
      watermark_image,
      no_watermark: nowm?(image_file),
      watermark_width: watermark_width,
      watermark_height: watermark_height
    )

    # stream image headers & bytes
    send_file_headers! options
    headers['Content-Length'] = data.length.to_s
    self.status = 200
    self.response_body = data

  rescue NotAdminException
    self.response_body = I18n.t 'neofiles.403_access_denied'
    self.content_type = 'text/plain; charset=utf-8'
    self.status = 403
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
end
