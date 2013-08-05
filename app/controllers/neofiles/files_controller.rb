# encoding: UTF-8
class Neofiles::FilesController < Neofiles::ServeController

  def show
    file = Neofiles::File.find params[:id]

    if file.is_a? Neofiles::Image
      redirect_to neofiles_image_path(params) and return
    end

    send_data file.data, {
      filename: file.filename,
      type: file.content_type || "application/octet-stream",
      disposition: "inline",
    }
  end
end
