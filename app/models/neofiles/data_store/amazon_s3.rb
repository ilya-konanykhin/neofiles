# Module for storing and reading files from Amazon S3
# If you want to work with amazon s3 you need set values for the following parameters in your config file
# amazon_s3_region - the AWS region to connect to. The region is used to construct the client endpoint.
# amazon_s3_api, amazon_s3_secret - used to set credentials statically
# bucket_name - storage name in amazon_s3. Bucket must have a name that conforms to the naming requirements for non-US Standard regions.
# http://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-s3-bucket-naming-requirements.html
# File will be named as id of the Neofiles::File object

require 'aws-sdk'

class Neofiles::DataStore::AmazonS3

  def self.bucket_name
    Rails.application.config.neofiles.amazon_s3_bucket
  end

  def self.find(id)
    s3_object = new(id)
    if s3_object.get_object
      s3_object
    else
      raise Neofiles::DataStore::NotFoundException
    end
  end



  attr_reader :id, :data, :length, :md5

  def initialize(id)
    @id = id
  end

  def get_object
    begin
      @s3_object ||= Rails.cache.fetch cache_key, expires_in: 1.hour do
        client.get_object(
            bucket: bucket_name,
            key: file_path
        )
      end
    rescue Aws::S3::Errors::ServiceError
      nil
    end
  end

  def data
    @data ||= get_object.body.read
  end

  def write(data)
    client.put_object(
        body: data,
        bucket: bucket_name,
        key: file_path
    )

    @data = data.is_a?(String) ? data : data.read
    @length = @data.length
    md5 = Digest::MD5.new
    md5 << @data
    @md5 = md5.hexdigest
  end



  private

  def file_path
    object_id = @id.to_s
    object_id[0..2] + '/' + object_id[3..4] + '/' + object_id
  end

  def cache_key
    ['Neofiles::DataStore::AmazonS3', @id, bucket_name, file_path]
  end

  def bucket_name
    self.class.bucket_name
  end

  def client
    begin
      @client ||= Aws::S3::Client.new(
          region: Rails.application.config.neofiles.amazon_s3_region,
          credentials: Aws::Credentials.new(
              Rails.application.config.neofiles.amazon_s3_api,
              Rails.application.config.neofiles.amazon_s3_secret
          )
      )
    rescue Aws::S3::Errors::ServiceError
      nil
    end
  end

end