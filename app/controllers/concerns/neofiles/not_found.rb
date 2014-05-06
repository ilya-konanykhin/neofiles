# encoding: UTF-8
module Neofiles::NotFound
  extend ActiveSupport::Concern

  include ActionController::Rescue

  included do
    rescue_from Mongoid::Errors::DocumentNotFound, with: :error_404

    def error_404
      self.response_body = "Ошибка 404: файл не найден"
      self.content_type = 'text/plain; charset=utf-8'
      self.status = 404
    end

    private :error_404
  end
end
