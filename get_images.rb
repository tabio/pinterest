require 'fileutils'
require 'json'
require 'net/http'
require 'open-uri'
require 'pinterest-api'
require 'pry'
require 'pp'
require 'uri'

class PinterestResponse
  class << self
    def parse(response)
      if response['data'].nil?
        pp response
        return []
      end

      next_url = response.dig('page', 'next')
      res = response['data'].each_with_object({}) do |data, result|
        result[data['id']] = data.dig('image', 'original')
      end

      [res, next_url]
    end
  end
end

class GetImageFromPinterest
  ACCESS_TOKEN = ''
  USER_NAME    = ''
  BOARDS       = %w[]
  SLEEP_COUNT  = 300

  attr_reader   :client
  attr_accessor :pinterest_responses

  def initialize
    @pinterest_responses = {}
    BOARDS.each do |board|
      pinterest_responses[board] = {}
    end
    @client = Pinterest::Client.new(ACCESS_TOKEN)
  end

  # Pinterestから対象のボード内の画像情報を取得
  def get_image_info
    BOARDS.each do |board|
      res = client.get_board_pins("#{USER_NAME}/#{board}", fields: 'image')
      data, next_url = PinterestResponse.parse(res)
      pinterest_responses[board].merge!(data)
      get_image_info_from_next_page(next_url, board)
    end
  end

  private

  def get_image_info_from_next_page(target_url, board)
    return if target_url.nil?

    url = URI.parse(target_url)
    req = Net::HTTP::Get.new(url.request_uri)
    req['User-Agent'] = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.103 Safari/537.36'
    res = Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
      http.request(req)
    end

    data, next_url = PinterestResponse.parse(JSON.parse(res.body)) rescue return
    pinterest_responses[board].merge!(data)

    sleep SLEEP_COUNT

    get_image_info_from_next_page(next_url, board)
  end
end

class DownloadImages
  class << self
    # Pinterestから画像を取得して保存
    def download(info)
      info.each do |board_name, data|
        original_dir = "#{board_name}/original"
        lgtm_dir     = "#{board_name}/lgtm"

        FileUtils.mkdir_p(original_dir)
        FileUtils.mkdir_p(lgtm_dir)

        data.each do |id, hash|
          url           = hash['url']
          base_name     = File.basename(url)
          original_file ="#{original_dir}/#{base_name}"
          lgtm_file     ="#{lgtm_dir}/#{base_name}"

          open(original_file, 'wb') do |save_file|
            open(url, 'rb') do |read_file|
              save_file.write(read_file.read)
            end
          end

          # 画像にLGTMを追加したものを作っておく
          size = font_size(hash['width'], hash['heigh'])
          cmd = "convert -pointsize #{size} -gravity Center -annotate 0 'LTGM' -fill white #{original_file} #{lgtm_file}"
          `#{cmd}`
        end
      end
    end

    private

    def font_size(width, height)
      (width / 4).floor
    end
  end
end

obj = GetImageFromPinterest.new
obj.get_image_info
DownloadImages.download(obj.pinterest_responses)
