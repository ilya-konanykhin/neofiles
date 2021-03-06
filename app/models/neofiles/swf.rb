# Special case of Neofiles::File for dealing with SWF movies.
#
# Alongside usual file things, stores width & height of Flash clip.
#
require_dependency 'image_spec'

class Neofiles::Swf < Neofiles::File

  class SwfFormatException < Exception; end

  field :width, type: Integer
  field :height, type: Integer

  before_save :compute_dimensions

  # Return array with width & height decorated with singleton function to_s returning 'WxH' string.
  def dimensions
    dim = [width, height]
    def dim.to_s
      join 'x'
    end
    dim
  end

  # Overrides parent "admin views" with square 100x100 Flash thumbnail.
  def admin_compact_view(view_context)
    view_context.neofiles_link self, view_context.tag(:img, src: view_context.image_path('neofiles/swf-thumb-100x100.png')), target: '_blank'
  end



  private

  # Store dimensions on #save.
  def compute_dimensions
    return unless @file

    spec = ::ImageSpec.new(@file)
    if spec.content_type != 'application/x-shockwave-flash'
      raise SwfFormatException.new I18n.t('neofiles.swf_type_incorrect', content_type: spec.content_type)
    end
    self.width = spec.width
    self.height = spec.height
  end
end