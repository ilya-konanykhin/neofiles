namespace :neofiles_transfer do

  task from_mongo_to_amazon_s3: :environment do
    Neofiles::File.pluck(:id).each do |id|
      begin
        mongo_object = Neofiles::DataStore::Mongo.find id
        Neofiles::DataStore::AmazonS3.new(id).write(mongo_object.data) if mongo_object
      rescue Neofiles::DataStore::NotFoundException
        next
      end
    end
  end

end



