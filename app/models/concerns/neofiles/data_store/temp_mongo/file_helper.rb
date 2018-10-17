module Neofiles::DataStore::TempMongo::FileHelper
  extend ActiveSupport::Concern

  included do
    has_many :temp_chunks, dependent: :destroy, order: [:n, :asc], class_name: 'Neofiles::TempFileChunk'
    field :chunk_size, type: Integer, default: Neofiles::DataStore::Mongo::DEFAULT_CHUNK_SIZE
    validates :chunk_size, presence: true

    def self.copy_from_temp_mongo_to_mongo(ids)
      ids.each do |id|
        begin
          file = Neofiles::File.find id
          if file.is_temp
            temp_object = Neofiles::DataStore::TempMongo.find id
            mongo_object = Neofiles::DataStore::Mongo.find id rescue nil
            unless mongo_object
              temp_file = Tempfile.new('temp_file').tap do |f|
                f.write(temp_object.data.force_encoding('UTF-8'))
              end
              Neofiles::DataStore::Mongo.new(id).write(temp_file)
              #temp_file.close
              #temp_file.delete
              file.update_attribute :is_temp, false
            end
          end
        rescue Neofiles::DataStore::NotFoundException
          next
        end
      end
    end

  end
end
