# encoding: UTF-8
class Neofiles::FilesController < ActionController::Metal

  include ActionController::DataStreaming
  include ActionController::Redirecting
  include Rails.application.routes.url_helpers
  include Neofiles::NotFound

  def show
    file = Neofiles::File.find params[:id]

    if file.is_a? Neofiles::Image
      redirect_to neofiles_image_path(params) and return
    end

    send_data file.data, {
      filename: file.filename,
      type: file.content_type,
      disposition: 'inline',
    }
  end
end
