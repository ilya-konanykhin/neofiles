# encoding: UTF-8
class Neofiles::ServeController < ApplicationController
  rescue_from Mongoid::Errors::DocumentNotFound, with: :error_404

  private

    def error_404
      render text: "Ошибка 404: файл не найден", status: :not_found
    end
end
