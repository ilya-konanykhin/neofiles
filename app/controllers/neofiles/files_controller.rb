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

    send_file_headers!({
      filename: CGI::escape(file.filename),
      type: file.content_type,
      disposition: 'inline',
    })

    self.status = 200
    self.response_body = file.data
  end
end
