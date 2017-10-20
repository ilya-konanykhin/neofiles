# Special case of Neofiles::File for dealing with images.
#
# Alongside usual file things:
# 1) stores width & height of image;
# 2) does some useful manipulations, like EXIF rotation & cleaning;
# 3) stores no_wm [no_watermark] flag to tell Neofiles::ImagesController not to put watermark automatically.
#
class Neofiles::Image < Neofiles::File

  class ImageFormatException < Exception; end

  field :width, type: Integer
  field :height, type: Integer

  field :no_wm, type: Mongoid::Boolean

  # Do useful stuf before calling parent #save from Neofiles::File.
  #
  # 1. Rotates image if orientation is present in EXIF and Rails.application.config.neofiles.image_rotate_exif == true.
  # 2. Cleans all EXIF data if Rails.application.config.neofiles.image_clean_exif == true.
  # 3. Crops input to some max size in case enormous 10000x10000 px input is provided
  #    (fill Rails.application.config.neofiles.image_max_dimensions with [w, h] or {width: w, height: h} or wh)
  #
  # Uses MiniMagick and works only with JPEG, PNG & GIF formats.
  #
  # TODO: переделать работу с файлом. Сейчас МиниМеджик копирует входной файл в темповую директорию, после его обработки
  # я делаю еще одну темповую копию и ее тут же читаю - неэкономно! Это сделано потому, что МиниМеджик не дает мне инфу
  # о своем темповом файле, если бы давал дескриптор или его имя, я бы его читал. Но я могу только считать содержимое
  # или попросить МиниМеджик скопировать его, что и происходит. Вариант: построить класс StringIO, который может читать
  # строку блоками, и натравить на image.to_blob (этот метод прочитает содержимое темпового файла), и уже этот поток
  # нарезать на чанки. Еще вариант: тупо пройтись по строке image.to_blob в цикле.
  def save_file

    return if @file.nil?

    begin
      image = ::MiniMagick::Image.read @file
    rescue ::MiniMagick::Invalid
      raise ImageFormatException.new I18n.t('neofiles.mini_magick_error')
    end

    # check input forma
    type = image[:format].downcase
    raise ImageFormatException.new I18n.t('neofiles.unsupported_image_type', type: type.upcase) unless type.in? %w{ jpeg gif png }

    # rotate from exit
    dimensions = image[:dimensions]
    if Rails.application.config.neofiles.image_rotate_exif
      case image['exif:orientation']
        when '3'
          image.rotate '180'
        when '6'
          image.rotate '90'
          dimensions.reverse!
        when '8'
          image.rotate '-90'
          dimensions.reverse!
      end
    end

    # clean exif
    image.strip if Rails.application.config.neofiles.image_clean_exif

    # crop to max size
    if crop_dimensions = Rails.application.config.neofiles.image_max_dimensions
      if crop_dimensions.is_a? Hash
        crop_dimensions = crop_dimensions.values_at :width, :height
      elsif !(crop_dimensions.is_a? Array)
        crop_dimensions = [crop_dimensions, crop_dimensions]
      end

      image.resize crop_dimensions.join('x').concat('>')
      dimensions = image[:dimensions]
    end

    # fill in some fields
    self.width = dimensions[0]
    self.height = dimensions[1]
    self.content_type = "image/#{type}"

    begin
      # make temp image
      tempfile = Tempfile.new 'neofiles-image'
      tempfile.binmode
      image.write tempfile

      # substitute file to be saved with the temp
      @file = tempfile

      # call super #save
      super

    ensure
      tempfile.close
      tempfile.unlink
    end

  ensure
    image.try :destroy! #delete mini_magick tempfile
  end

  # Return array with width & height decorated with singleton function to_s returning 'WxH' string.
  def dimensions
    dim = [width, height]
    def dim.to_s
      join 'x'
    end
    dim
  end

  # Set no_wm from HTML form (value is a string '1'/'0').
  def no_wm=(value)
    write_attribute :no_wm, value.is_a?(String) ? value == '1' : value
  end
end
