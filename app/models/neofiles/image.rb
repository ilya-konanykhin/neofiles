class Neofiles::Image < Neofiles::File

  field :width, type: Integer
  field :height, type: Integer

  field :no_wm, type: Mongoid::Boolean

  # Если нужно перед сохранением обрезать картинку, нужно сюда записать в одном из форматов:
  #   [w, h]
  #   {width: w, height: h}
  #   wh # если одно значение на обе стороны
  attr_accessor :crop_before_save

  # Перед сохранением обработаем поворот картинки (если есть инфа) и запишем ширину и высоту.
  # Обязательно вызовем родительский save_file.
  #
  # После поворота вся информация из Экзифа стирается, чтобы потом не мешать и еще раз не поворачивать. Нужно ли это?
  #
  # TODO: переделать работу с файлом. Сейчас МиниМеджик копирует входной файл в темповую директорию, после его обработки
  # я делаю еще одну темповую копию и ее тут же читаю - неэкономно! Это сделано потому, что МиниМеджик не дает мне инфу
  # о своем темповом файле, если бы давал дескриптор или его имя, я бы его читал. Но я могу только считать содержимое
  # или попросить МиниМеджик скопировать его, что и происходит. Вариант: построить класс StringIO, который может читать
  # строку блоками, и натравить на image.to_blob (этот метод прочитает содержимое темпового файла), и уже этот поток
  # нарезать на чанки. Еще вариант: тупо пройтись по строке image.to_blob в цикле.
  def save_file

    return if @file.nil?

    # откроем файл для обработки
    begin
      image = ::MiniMagick::Image.read @file
    rescue ::MiniMagick::Invalid
      raise 'The supplied image is invalid, cannot process it'
    end

    # какой тип у картинки, мы вообще такие берем?
    type = image[:format].downcase
    raise "Unsupported image format #{type.upcase}" unless type.in? %w{ jpeg gif png }

    # повернем картинку, если она была сфотана "криво"
    dimensions = image[:dimensions]
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

    # уберем все левые данные (нужно ли?)
    image.strip

    # обрежем, если нужно
    if crop_dimensions = crop_before_save
      if crop_dimensions.is_a? Hash
        crop_dimensions = crop_dimensions.values_at :width, :height
      elsif !(crop_dimensions.is_a? Array)
        crop_dimensions = [crop_dimensions, crop_dimensions]
      end

      image.resize crop_dimensions.join('x').concat('>')
      dimensions = image[:dimensions]
    end

    # сохраним ширину, высоту и тип
    self.width = dimensions[0]
    self.height = dimensions[1]
    self.content_type = "image/#{type}"

    begin

      # запишем картинку в темп
      tempfile = Tempfile.new 'neofiles-image'
      tempfile.binmode
      image.write tempfile

      # подменим загружаемый файл нашим временным с результатом обработки
      @file = tempfile

      # наконец, вызовем родительский код для сохранения файла в чанках + всякие поля md5 и прочие
      super

    ensure
      tempfile.close
      tempfile.unlink
    end
  end

  def dimensions
    dim = [width, height]
    def dim.to_s
      join 'x'
    end
    dim
  end

  # Как будет выглядеть в админке этот файл в "компактном" представлении (при загрузке, в альбомах и т. п.)
  # Картинка показывается в виде ссылки с необрезанной иконкой 100 на 100.
  def admin_compact_view(template)
    # _path а не _url, чтобы не потерять админскую сессионную куку при переходе на другой домен
    url_method = Neofiles.is_admin?(template) ? :neofiles_image_nowm_path : :neofiles_image_path
    template.neofiles_img_link self, 100, 100, {}, target: '_blank', href: template.send(url_method, self)
  end

  def no_wm=(value)
    write_attribute :no_wm, value.is_a?(String) ? value == "1" : value
  end

end