require 'open-uri'
require 'ssrf_filter'
require 'addressable'
require 'carrierwave/downloader/remote_file'
require 'net/http'
require 'net/https'
require 'uri'

module CarrierWave
  module Downloader
    class Base
      attr_reader :uploader

      def initialize(uploader)
        @uploader = uploader
      end

      ##
      # Downloads a file from given URL and returns a RemoteFile.
      #
      # === Parameters
      #
      # [url (String)] The URL where the remote file is stored
      # [remote_headers (Hash)] Request headers
      #
      def download(url, remote_headers = {})
        headers = remote_headers.
          reverse_merge('User-Agent' => "CarrierWave/#{CarrierWave::VERSION}")
        uri = process_uri(url.to_s)
        puts uri
        begin
          if skip_ssrf_protection?(uri)
            response = OpenURI.open_uri(process_uri(url.to_s), headers)
          else
            request = ::Net::HTTP::Get.new(uri)
            request['host'] = uri.hostname
            puts uri.hostname
            response = Net::HTTP.start(uri.hostname, uri.port, 'httpproxy-tcop.vip.ebay.com', '80', :use_ssl => uri.scheme == 'https') do |http|
              http.request(request)
            end
            response.uri = request.uri
            response.value
          end
        rescue StandardError => e
          raise CarrierWave::DownloadError, "could not download file: #{e.message}"
        end
        CarrierWave::Downloader::RemoteFile.new(response)
      end

      ##
      # Processes the given URL by parsing it, and escaping if necessary. Public to allow overriding.
      #
      # === Parameters
      #
      # [url (String)] The URL where the remote file is stored
      #
      def process_uri(uri)
        uri_parts = uri.split('?')
        encoded_uri = Addressable::URI.parse(uri_parts.shift).normalize.to_s
        query = uri_parts.any? ? "?#{uri_parts.join('?')}" : ''
        begin
          URI.parse("#{encoded_uri}#{query}")
        rescue URI::InvalidURIError
          URI.parse("#{encoded_uri}#{URI::DEFAULT_PARSER.escape(query)}")
        end
      rescue URI::InvalidURIError, Addressable::URI::InvalidURIError
        raise CarrierWave::DownloadError, "couldn't parse URL: #{uri}"
      end

      ##
      # If this returns true, SSRF protection will be bypassed.
      # You can override this if you want to allow accessing specific local URIs that are not SSRF exploitable.
      #
      # === Parameters
      #
      # [uri (URI)] The URI where the remote file is stored
      #
      # === Examples
      #
      #     class CarrierWave::Downloader::CustomDownloader < CarrierWave::Downloader::Base
      #       def skip_ssrf_protection?(uri)
      #         uri.hostname == 'localhost' && uri.port == 80
      #       end
      #     end
      #
      #     my_uploader.downloader = CarrierWave::Downloader::CustomDownloader
      #
      def skip_ssrf_protection?(uri)
        false
      end
    end
  end
end
