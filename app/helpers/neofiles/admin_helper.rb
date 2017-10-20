module Neofiles::AdminHelper

  # Renders admin view template, @see Neofiles::AdminController#file_compact.
  # Each Neofiles::File class descendant must have a $VIEW_TYPE view template
  # located in app/views/neofiles/$VIEW_TYPE/_$CLASSNAME.slim, e.g. _image.slim
  # where $VIEW_TYPE is a :compact, :full etc.
  def neofiles_render_admin_view(file, view_type)
    render view_by_class_type(file.class.name, view_type), file: file
  end

  private

  # Returns path to admin view template by Neofiles::File class name and type
  def view_by_class_type(class_name, view_type)
    class_name.underscore.sub(/\//, "/#{view_type}/")
  end
end
