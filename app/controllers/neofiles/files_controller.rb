# Controller that serves files from the database via single action #show.
#
# If the file requested is an image redirect to Neofiles::ImagesController is made.
#
class Neofiles::FilesController < ActionController::Metal

  include ActionController::DataStreaming
  include ActionController::Redirecting
  include Rails.application.routes.url_helpers
  include Neofiles::NotFound

  def show
    file = Neofiles::File.find params[:id]

    if file.is_a? Neofiles::Image
      options = params.values_at(:format, :crop, :quality)
      redirect_to neofiles_image_path(options), status: 301 and return
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
