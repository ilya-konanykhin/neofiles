require_dependency 'image_spec'

class Neofiles::Swf < Neofiles::File

  class SwfFormatException < Exception; end

  field :width, type: Integer
  field :height, type: Integer

  before_save :compute_dimensions

  def dimensions
    dim = [width, height]
    def dim.to_s
      join 'x'
    end
    dim
  end

  # Как будет выглядеть в админке этот файл в "компактном" представлении (при загрузке, в альбомах и т. п.)
  # Картинка показывается в виде ссылки с необрезанной иконкой 100 на 100.
  def admin_compact_view(view_context)
    view_context.neofiles_link self, view_context.tag(:img, src: view_context.image_path('neofiles/swf-thumb-100x100.png')), target: '_blank'
  end



  private

  # При сохранении запишем ширину и высоту файла.
  def compute_dimensions
    return unless @file

    spec = ::ImageSpec.new(@file)
    if spec.content_type != 'application/x-shockwave-flash'
      raise SwfFormatException.new "File pretends to be SWF, but it is not, determined content type is #{spec.content_type}"
    end
    self.width = spec.width
    self.height = spec.height
  end
end