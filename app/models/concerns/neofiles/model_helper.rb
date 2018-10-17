module Neofiles::ModelHelper
  extend ActiveSupport::Concern

  included do
    after_validation :save_temp_files, on: [:create, :update]

    private

    def save_temp_files
      Neofiles::File.copy_from_temp_mongo_to_mongo get_file_ids
    end

    def get_file_ids
      []
    end
  end
end
