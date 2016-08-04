# Return 404 NOT FOUND response when requested file is not found in the database.
#
# This concern is to be included in serving controllers (Files/ImagesController).
#
module Neofiles::NotFound
  extend ActiveSupport::Concern

  include ActionController::Rescue

  included do
    rescue_from Mongoid::Errors::DocumentNotFound, with: :error_404

    def error_404
      self.response_body = I18n.t('neofiles.404_not_found')
      self.content_type = 'text/plain; charset=utf-8'
      self.status = 404
    end

    private :error_404
  end
end
