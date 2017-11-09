module Neofiles::FileChunkHelper
  extend ActiveSupport::Concern

  included do
    include Mongoid::Document

    belongs_to :file, class_name: 'Neofiles::File'

    field :n, type: Integer, default: 0 # что это за поле?
    field :data, type: BSON::Binary

    index({file_id: 1, n: 1}, background: true)

    def to_s
      data.data
    end
  end
end
