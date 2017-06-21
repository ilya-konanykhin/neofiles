module Neofiles::DataStore::Mongo::FileHelper
  extend ActiveSupport::Concern

  included do
    has_many :chunks, dependent: :destroy, order: [:n, :asc], class_name: 'Neofiles::FileChunk'
    field :chunk_size, type: Integer, default: Neofiles::DataStore::Mongo::DEFAULT_CHUNK_SIZE
    validates :chunk_size, presence: true

    def self.copy_from_mongo_to_amazon_s3(ids)
      ids.each do |id|
        begin
          mongo_object = Neofiles::DataStore::Mongo.find id
          amazon_object = Neofiles::DataStore::AmazonS3.new(id).data
          if mongo_object && !amazon_object
            Neofiles::DataStore::AmazonS3.new(id).write(mongo_object.data)
          end
        rescue Neofiles::DataStore::NotFoundException
          next
        end
      end
    end

  end
end