# encoding: UTF-8
class Neofiles::ImagesController < Neofiles::ServeController
  MAX_WIDTH = 2000
  MAX_HEIGHT = 2000

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

      # потребный формат
      width, height = params[:format].split('x').map(&:to_i)
      watermark_width, watermark_height = width, height
      raise Mongoid::Errors::DocumentNotFound unless width.between?(1, MAX_WIDTH) and height.between?(1, MAX_HEIGHT)

      # откроем файл с картинкой
      image = MiniMagick::Image.read(data)

      # нужна обрезка?
      if Neofiles.crop_requested? params

        # 1) уменьшим минимум до WxH (результат может быть больше по одной из сторон)
        # 2) привяжемся к центру
        # 3) отрежем все, что выступает
        image.combine_options do |c|
          c.resize "#{width}x#{height}^"
          c.gravity "center"
          c.extent "#{width}x#{height}"
        end

      else

        # обрезка не нужна, впишем в формат WxH с сохранением пропорций (результат может отличаться по одной стороне)
        image.resize "#{width}x#{height}"

      end

      data = image.to_blob
      watermark_image = image
      options[:type] = image.mime_type
    end

    # добавим водяной знак, если нужно
    data = watermark_image(watermark_image, (watermark_width * 0.25).ceil) if watermark_width >= 300 && watermark_height >= 300

    send_data data, options
  end

  private

    # поставить водяной знак, image — поток или MiniMagick::Image
    def watermark_image(image, preferred_width = nil)
      image = MiniMagick::Image.read image unless image.is_a? MiniMagick::Image

      image.composite(MiniMagick::Image.open(Rails.root.join("app", "assets", "images", "watermark.png"))) do |c|
        c.gravity 'south'
        preferred_width = [200, preferred_width].max if preferred_width > 0
        c.geometry "#{preferred_width}x+0+20"
      end.to_blob
    end
end
