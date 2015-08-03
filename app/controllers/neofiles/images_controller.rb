# encoding: UTF-8
class Neofiles::ImagesController < ActionController::Metal

  class NotAdminException < Exception; end

  include ActionController::DataStreaming
  include ActionController::RackDelegation
  include Neofiles::NotFound

  if defined?(Devise)
    include ActionController::Helpers
    include Devise::Controllers::Helpers
  end

  MAX_WIDTH = 2000
  MAX_HEIGHT = 2000

  # Получить картинку из базы. Доступные параметры:
  #
  #   format: '100x200'   — вернуть не больше этого размера, подпараметры:
  #     crop: 1/0         - если 1, то обрезать лишнее, а не вписывать в указанный прямоугольник
  #     quality: [1-100]  - качество картинки на выходе, с принудительным преобразованием в JPEG
  #
  # Водяной знак добавляется автоматом из картинки /assets/images/neofiles-watermark.png, если размер получающейся
  # картинки больше некоего предела (даже если обрезки нет).
  #
  # Если передан параметр nowm, и человек админ, то не ставим водяной знак.
  def show

    # получим, проверим
    image_file = Neofiles::Image.find params[:id]

    # данные для отсылки
    data = image_file.data
    options = {
      filename: CGI::escape(image_file.filename),
      type: image_file.content_type || 'image/jpeg',
      disposition: 'inline',
    }

    # нужно ли форматировать?
    watermark_image, watermark_width, watermark_height = data, image_file.width, image_file.height
    if params[:format].present?

      width, height = params[:format].split('x').map(&:to_i)
      watermark_width, watermark_height = width, height
      raise Mongoid::Errors::DocumentNotFound unless width.between?(1, MAX_WIDTH) and height.between?(1, MAX_HEIGHT)

      quality = [[Neofiles::quality_requested(params), 100].min, 1].max if Neofiles::quality_requested?(params)
      setting_quality = quality && options[:type] == 'image/jpeg'

      image = MiniMagick::Image.read(data)

      if Neofiles.crop_requested? params
        # запрошена обрезка:
        # 1) уменьшим минимум до WxH (результат может быть больше по одной из сторон)
        # 2) привяжемся к центру
        # 3) отрежем все, что выступает
        # 4) установим качество, если надо
        image.combine_options do |c|
          c.resize "#{width}x#{height}^"
          c.gravity "center"
          c.extent "#{width}x#{height}"
          c.quality "#{quality}" if setting_quality
        end
      else
        # обрезка не нужна, впишем в формат WxH с сохранением пропорций (результат может отличаться по одной стороне)
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

      # если запросили качество, но мы его не ставили — значит, формат картинки не подходит, и надо пересохранить в JPEG
      if quality && !setting_quality
        image.format 'jpeg'
        image.quality quality.to_s
      end

      data = image.to_blob
      watermark_image = image
      options[:type] = image.mime_type
    end

    watermark_image = MiniMagick::Image.read watermark_image unless watermark_image.is_a? MiniMagick::Image

    # добавим водяной знак, если нужно
    data = Rails.application.config.neofiles.watermarker.(
      watermark_image,
      no_watermark: nowm?(image_file),
      watermark_width: watermark_width,
      watermark_height: watermark_height
    )

    send_file_headers! options
    headers['Content-Length'] = data.length.to_s
    self.status = 200
    self.response_body = data

  rescue NotAdminException
    self.response_body = "Ошибка 403: недостаточно прав для получения файла в таком формате"
    self.content_type = 'text/plain; charset=utf-8'
    self.status = 403
  end



  private

    # поставить водяной знак, image — поток или MiniMagick::Image
    def watermark_image(image, preferred_width = nil)
      image = MiniMagick::Image.read image unless image.is_a? MiniMagick::Image

      image.composite(MiniMagick::Image.open(Rails.root.join("app", "assets", "images", "neofiles-watermark.png"))) do |c|
        c.gravity 'south'
        preferred_width = [200, preferred_width].max if preferred_width > 0
        c.geometry "#{preferred_width}x+0+20"
      end.to_blob
    end

    def nowm?(image_file)
      image_file.no_wm? || (params[:nowm] == true && admin_or_die)
    end

    def admin_or_die
      if Neofiles.is_admin? self
        true
      else
        raise NotAdminException
      end
    end
end
