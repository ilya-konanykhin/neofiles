# Module for storing and reading files from Amazon S3
# If you want to work with amazon s3 you need set values for the following parameters in your config file
# amazon_s3_region - the AWS region to connect to. The region is used to construct the client endpoint.
# amazon_s3_api, amazon_s3_secret - used to set credentials statically
# amazon_s3_endpoint - change if using another S3-compatible provider
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
    if s3_object.data
      s3_object
    else
      raise Neofiles::DataStore::NotFoundException
    end
  end



  attr_reader :id, :data, :length, :md5

  def initialize(id)
    @id = id
  end

  def data
    @data ||= client.get_object(
          bucket: bucket_name,
          key: s3_key
      ).body.read
  rescue Aws::S3::Errors::ServiceError
    nil
  end

  def length
    @length ||= data.length
  end

  def md5
    @md5 ||= begin
      md5 = Digest::MD5.new
      md5 << data
      md5.hexdigest
    end
  end

  def write(data)
    if data.is_a? Tempfile
      data.flush
      data.rewind
      data = data.read
    end

    client.put_object(
        body: data,
        bucket: bucket_name,
        key: s3_key
    )
    @data = data
  end



  private

  def s3_key
    object_id = @id.to_s
    object_id[0..1] + '/' + object_id[2..4] + '/' + object_id
  end

  def bucket_name
    self.class.bucket_name
  end

  def client
    @client ||= Aws::S3::Client.new(client_params)
  rescue Aws::S3::Errors::ServiceError
    nil
  end

  def client_params
    {
      region: Rails.application.config.neofiles.amazon_s3_region,
      credentials: Aws::Credentials.new(
        Rails.application.config.neofiles.amazon_s3_api,
        Rails.application.config.neofiles.amazon_s3_secret
      )
    }.tap do |result|
      if Rails.application.config.neofiles.amazon_s3_endpoint
        result[:endpoint] = Rails.application.config.neofiles.amazon_s3_endpoint
      end
    end
  end

end