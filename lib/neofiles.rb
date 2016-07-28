require 'neofiles/engine'

module Neofiles
  # maybe config

  mattr_accessor :routes_proc
  @@routes_proc = proc do
    scope 'neofiles', module: :neofiles do
      get  '/admin/file_compact/', to: 'admin#file_compact', as: 'neofiles_file_compact'
      post '/admin/file_save/', to: 'admin#file_save', as: 'neofiles_file_save'
      post '/admin/file_remove/', to: 'admin#file_remove', as: 'neofiles_file_remove'
      post '/admin/file_update/', to: 'admin#file_update', as: 'neofiles_file_update'

      post '/admin/redactor-upload/', to: 'admin#redactor_upload', as: 'neofiles_redactor_upload'
      get  '/admin/redactor-list/:owner_type/:owner_id/:type', to: 'admin#redactor_list', as: 'neofiles_redactor_list'

      get  '/serve/:id', to: 'files#show', as: 'neofiles_file'
      get  '/serve-image/:id(/:format(/c:crop)(/q:quality))', to: 'images#show', as: 'neofiles_image', constraints: {format: /[1-9]\d*x[1-9]\d*/, crop: /[10]/, quality: /[1-9]\d*/}

      # получаем полную картинку без водяного знака
      # путь начинается с nowm, чтобы nginx не кэшировал его, наравне с /serve*
      get  '/nowm-serve-image/:id', to: 'images#show', as: 'neofiles_image_nowm', defaults: {nowm: true}
    end
  end



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
    return nil if image_file.nil?

    if image_file.is_a? Neofiles::Image
      image_file_width = image_file.width
      image_file_height = image_file.height
    else
      image_file_width = image_file[:width]
      image_file_height = image_file[:height]
    end

    return if image_file_width.blank? || image_file_height.blank?

    # построим запрос к ИмейджМеджику
    command = MiniMagick::CommandBuilder.new(:convert)            # команда convert
    command.size([image_file_width, image_file_height].join 'x')  # габариты входного файла
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

  def is_admin?(context)
    Rails.application.config.neofiles.try(:current_admin).try(:call, context)
  end

  module_function :resized_image_dimensions, :crop_requested?, :quality_requested?, :quality_requested, :is_admin?
end
