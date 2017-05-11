class Neofiles::DataStore::Mongo::FileHelper
  extend ActiveSupport::Concern

  included do
    has_many :chunks, dependent: :destroy, order: [:n, :asc], class_name: 'Neofiles::FileChunk'
    field :chunk_size, type: Integer, default: Neofiles::DataStore::Mongo::DEFAULT_CHUNK_SIZE
    validates :chunk_size, presence: true
  end
end