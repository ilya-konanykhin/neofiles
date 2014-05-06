# encoding: UTF-8
class Neofiles::ImagesController < ActionController::Metal

  include Neofiles::NotFound

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
  def show

    # получим, проверим
    image_file = Neofiles::Image.find params[:id]

    # данные для отсылки
    data = image_file.data
    options = {
      filename: image_file.filename,
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

    # добавим водяной знак, если нужно
    data = watermark_image(watermark_image, (watermark_width * 0.25).ceil) if watermark_width >= 300 && watermark_height >= 300

    headers['Content-Length'] = data.length.to_s
    self.response_body = data
    self.content_type = options[:type]
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
end
