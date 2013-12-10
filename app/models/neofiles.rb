# encoding: UTF-8
module Neofiles
  # Высчитать ширину и высоту картинки, которая получится после обрезки. image_file может быть как объектом, так и ID.
  # Вернет массив с шириной [0] и высотой [1] или nil, если что-то сломается по дороге (нет объекта, у него нет ширины
  # или высоты и т. п.)
  # resize_options такие же, как при запросе get_image, например, :crop => '1'.
  #
  # Для определения ширины и высоты может делать вызов MiniMagick, если сам не сможет.
  def resized_image_dimensions(image_file, width, height, resize_options)
    # если нужна обрезка, ширина и высота будут точно соотв. заданным
    return width, height if crop_requested? resize_options

    # обрезка не нужна, значит, надо вычислить ширину и высоту, сами делать не будем, спросим МиниМеджик
    image_file = Neofiles::Image.find image_file if image_file.is_a?(String)
    return nil if image_file.nil? or not(image_file.is_a? Neofiles::Image) or image_file.width.blank? or image_file.height.blank?

    # построим запрос к ИмейджМеджику
    command = MiniMagick::CommandBuilder.new(:convert)            # команда convert
    command.size([image_file.width, image_file.height].join 'x')  # габариты входного файла
    command.xc('white')                                           # входной файл число белый
    command.resize([width, height].join 'x')                      # изменить размер до нужного
    command.push('info:-')                                        # вывести (вернуть) инфу о файле

    # результат запроса будет таким: xc:white XC 54x100 54x100+0+0 16-bit DirectClass 0.070u 0:00.119
    # вытащим из него ширину и высоту и вернем в виде массива целых чисел
    MiniMagick::Image.new(nil, nil).run(command).match(/ (\d+)x(\d+) /).values_at(1, 2).map(&:to_i)

  rescue
    nil
  end

  def crop_requested?(params)
    params[:crop].present? and params[:crop] != '0'
  end

  def quality_requested?(params)
    !!quality_requested(params)
  end

  def quality_requested(params)
    params[:quality].to_i if params[:quality].present? and params[:quality] != '0'
  end

  module_function :resized_image_dimensions, :crop_requested?, :quality_requested?, :quality_requested
end