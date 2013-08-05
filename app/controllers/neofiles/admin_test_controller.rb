# encoding: UTF-8
class Neofiles::AdminTestController < ApplicationController
  def file_compact
    @file_id = request[:id]
  end
end