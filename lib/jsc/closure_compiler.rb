require 'rubygems'  # include RubyGems
gem 'activesupport' # load ActiveSupport
require 'activesupport' # include ActiveSupport
require 'active_support/core_ext/integer/inflections'

require 'json'
require 'net/http'

# Link to Google Closure Compiler service
GOOGLE_SERVICE_ADDRESS = "http://closure-compiler.appspot.com/compile"
# Default output_info parameter
DEFAULT_SERVICE = "compiled_code"
# Default compilation_level parameter
DEFAULT_LEVEL = "SIMPLE_OPTIMIZATIONS"

module JSCompiler

  class << self

    # Creates the <em>JSON</em> hash for the request and returns the hash to send along with the request
    #
    # Accepted parameters:
    # * <b>code</b>: json_code parameter
    # * <b>level</b>: compilation_level parameter
    def create_json_request(code)
      parameters = {
    	"code" => code,
	"level" => @level,
	"format"   => "json",
	"info"  => @op
      }
    end

    # Sends the JSON request <em>data</em> hash to Google service and returns its response
    #
    def post_to_cc(data)
      post_args = { 
        'js_code' => data["code"],
        'compilation_level' => data["level"],
        'output_format' => data["format"],
        'output_info' => data["info"]
      }
      # send the request
      resp, data = Net::HTTP.post_form(URI.parse(GOOGLE_SERVICE_ADDRESS), post_args)
    end

    # Compiles a file or a piece of code and returns parsed output
    #
    # Accepted parameters:
    # * <b>arg</b>: the code or the file path to compile
    # * <b>is_file</b>: 0 => arg is code
    #                   1 => arg is a file path
    # * <b>op</b>: output_info parameter
    # * <b>level</b>: compilation_level parameter
    def compile(arg, is_file, op, level)
      @op = op.blank? ? DEFAULT_SERVICE : op
      @level = level.blank? ? DEFAULT_LEVEL : level
      value = true

      if is_file
        js_code, value = read_file(arg)
      else
        js_code = arg
      end
      # js_code = is_file ? read_file(arg) : arg

      unless value
        return "Error reading file #{arg}"
      end

      begin
        resp, data = post_to_cc(create_json_request(js_code))
      rescue
        return "Error calling the service...try again later"
      end

      parse_json_output(data)
    end

    # Calls compile method for every file in <em>dir</em> directory
    #
    # Accepted parameters:
    # * <b>dir</b>: the directory
    # * <b>op</b>: output_info parameter
    # * <b>level</b>: compilation_level parameter
    def compile_dir(dir, op, level)
      out = String.new
      Dir.entries(dir).each do |file|
        if File.extname(file) == ".js"
          out << "Statistics for file #{file}...\n"
          out << compile(file, true, op, level) + "\n***************\n"
        end
      end
      return out
    end

    # Parses and returns JSON server <em>response</em>
    #
    # Accepted parameters:
    # * <b>response</b>: the server response
    def parse_json_output(response)
      out = String.new
      parsed_response = JSON.parse(response, :max_nesting => false)

      if parsed_response.has_key?("serverErrors") 
        result = parsed_response['serverErrors']
        return "Server Error: #{result[0]['error']} - Error Code: #{result[0]['code']}"
      end

      case @op
      when "compiled_code"
        out = parsed_response['compiledCode']
      when "statistics"
        result = parsed_response['statistics']
        out = create_statistics_output(result)
      else "errors"
        #case for errors or warnings
        begin
          result = parsed_response[@op]
          unless result.nil?
            num = result.size
            out << "You've got #{result.size} #{@op}\n\n"
            i = 0
            result.each do |message|
              i += 1
              out << "#{@op.singularize.capitalize} n.#{i}\n"
              out << "\t#{message['type']}: " + message[@op.singularize] + " at line #{message['lineno']} character #{message['charno']}\n"
              out << "\t" + message['line'] + "\n" unless message['line'].nil?
              out << "\t----------------\n"
            end
            return out
          else
            return "No #{@op}"
          end
        rescue
          out = "Error parsing JSON output...Check your output"
        end
      end
    end

    # Reads file and returns its content
    #
    # Accepted parameters:
    # * <b>file_name</b>: the absolute path to the file
    def read_file(file_name)
      begin
        content = File.open(file_name).read
        return content, true
      rescue
        puts "SI"
        out = "ERROR reading #{file_name} file"
#        return out, false
      end
    end

    # Parses and returns the <em>result</em> JSON server response
    #
    # Accepted parameters:
    # * <b>result</b>: the already parsed JSON server response
    def create_statistics_output(result)
      size_improvement = result['originalSize'] - result['compressedSize']
      size_gzip_improvement = result['originalGzipSize'] - result['compressedGzipSize']
      rate_improvement = (size_improvement * 100)/result['originalSize']
      rate_gzip_improvement = (size_gzip_improvement * 100)/result['originalGzipSize']
      out = "Original Size: #{result['originalSize']} bytes (#{result['originalGzipSize']} bytes gzipped) \n"
      out << "Compiled Size: #{result['compressedSize']} bytes (#{result['compressedGzipSize']} bytes gzipped) \n"
      out << "\t Saved #{rate_improvement}% off the original size (#{rate_gzip_improvement}% off the gzipped size)"
    end

  end

end
