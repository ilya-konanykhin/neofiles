# encoding: UTF-8
class Neofiles::FileChunk

  bson = defined?(Moped::BSON) ? Moped::BSON : BSON

  include Mongoid::Document

  store_in collection: "files.chunks", session: "neofiles"

  belongs_to :file, class_name: 'Neofiles::File'

  field :n, type: Integer, default: 0 # что это за поле?
  field :data, type: bson::Binary

  def to_s
    data.data
  end
end