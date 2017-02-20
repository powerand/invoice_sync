$:.unshift File.dirname(__FILE__)

require 'socket'
require 'byebug'
require 'redis'
require 'crc32'
require 'timeout'

PART_NUMS = %w(0 1 2 3)
ROOT = File.dirname(File.expand_path(__FILE__))
WEB_ROOT = File.join(ROOT, 'public')
HDD_STORE = File.join(ROOT, 'hdd-store')
HDD_STORE_WEB_ROOT = File.join(HDD_STORE, 'public')
REDIS = Redis.new(path: '/tmp/redis.sock')
THREADS = []
HTML_DELIMIER = ';%20'

def ramdisk_mounted
  !`mount|grep public`.empty?
end

Signal.trap("INT") do
  puts "exiting"
  @exiting = 1
  @backup_thread.join
  system "umount #{WEB_ROOT}"
  exit
end

SERVER = TCPServer.new 81

SERVER.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
SERVER.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPIDLE, 50)
SERVER.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPINTVL, 10)
SERVER.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPCNT, 5)
BLOCK_SIZE = 64
EOL = "\r\n"
HBD = "\r\n\r\n"
CONTENT_TYPE_MAPPING = {
  '.html' => 'text/html',
  '.txt' => 'text/plain',
  '.png' => 'image/png',
  '.jpg' => 'image/jpeg',
  '.css' => 'text/css',
  '.js'  => 'application/javascript',
  '.ttf' => 'application/x-font-ttf',
  '.ico' => 'image/x-icon',
  '.sql' => 'application/sql',
  '.tar.gz' => 'application/tar+gzip'
}
DEFAULT_CONTENT_TYPE = 'text/html'
DIR_INDEX = 'index.html'
DEFAULT_CHARSET = 'UTF-8'
URL_ENCODE_MAP = {'%20'=>' ','%21'=>'!','%22'=>'"','%23'=>'#','%24'=>'$','%25'=>'%','%26'=>'&','%27'=>'\'','%28'=>'(','%29'=>')','%2A'=>'*','%2B'=>'+','%2C'=>',','%2D'=>'-','%2E'=>'.','%2F'=>'/','%30'=>'0','%31'=>'1','%32'=>'2','%33'=>'3','%34'=>'4','%35'=>'5','%36'=>'6','%37'=>'7','%38'=>'8','%39'=>'9','%3A'=>':','%3B'=>';','%3C'=>'<','%3D'=>'=','%3E'=>'>','%3F'=>'?','%40'=>'@','%41'=>'A','%42'=>'B','%43'=>'C','%44'=>'D','%45'=>'E','%46'=>'F','%47'=>'G','%48'=>'H','%49'=>'I','%4A'=>'J','%4B'=>'K','%4C'=>'L','%4D'=>'M','%4E'=>'N','%4F'=>'O','%50'=>'P','%51'=>'Q','%52'=>'R','%53'=>'S','%54'=>'T','%55'=>'U','%56'=>'V','%57'=>'W','%58'=>'X','%59'=>'Y','%5A'=>'Z','%5B'=>'[','%5C'=>'\\','%5D'=>']','%5E'=>'^','%5F'=>'_','%60'=>'`','%61'=>'a','%62'=>'b','%63'=>'c','%64'=>'d','%65'=>'e','%66'=>'f','%67'=>'g','%68'=>'h','%69'=>'i','%6A'=>'j','%6B'=>'k','%6C'=>'l','%6D'=>'m','%6E'=>'n','%6F'=>'o','%70'=>'p','%71'=>'q','%72'=>'r','%73'=>'s','%74'=>'t','%75'=>'u','%76'=>'v','%77'=>'w','%78'=>'x','%79'=>'y','%7A'=>'z','%7B'=>'{','%7C'=>'|','%7D'=>'}','%7E'=>'~','%7F'=>' ','%E2%82%AC'=>'`','%81'=>'','%E2%80%9A'=>'‚','%C6%92'=>'ƒ','%E2%80%9E'=>'„','%E2%80%A6'=>'…','%E2%80%A0'=>'†','%E2%80%A1'=>'‡','%CB%86'=>'ˆ','%E2%80%B0'=>'‰','%C5%A0'=>'Š','%E2%80%B9'=>'‹','%C5%92'=>'Œ','%C5%8D'=>'','%C5%BD'=>'Ž','%8F'=>'','%C2%90'=>'','%E2%80%98'=>'‘','%E2%80%99'=>'’','%E2%80%9C'=>'“','%E2%80%9D'=>'”','%E2%80%A2'=>'•','%E2%80%93'=>'–','%E2%80%94'=>'—','%CB%9C'=>'˜','%E2%84'=>'™','%C5%A1'=>'š','%E2%80'=>'›','%C5%93'=>'œ','%9D'=>'','%C5%BE'=>'ž','%C5%B8'=>'Ÿ','%C2%A0'=>' ','%C2%A1'=>'¡','%C2%A2'=>'¢','%C2%A3'=>'£','%C2%A4'=>'¤','%C2%A5'=>'¥','%C2%A6'=>'¦','%C2%A7'=>'§','%C2%A8'=>'¨','%C2%A9'=>'©','%C2%AA'=>'ª','%C2%AB'=>'«','%C2%AC'=>'¬','%C2%AD'=>'%','%C2%AE'=>'®','%C2%AF'=>'¯','%C2%B0'=>'°','%C2%B1'=>'±','%C2%B2'=>'²','%C2%B3'=>'³','%C2%B4'=>'´','%C2%B5'=>'µ','%C2%B6'=>'¶','%C2%B7'=>'·','%C2%B8'=>'¸','%C2%B9'=>'¹','%C2%BA'=>'º','%C2%BB'=>'»','%C2%BC'=>'¼','%C2%BD'=>'½','%C2%BE'=>'¾','%C2%BF'=>'¿','%C3%80'=>'À','%C3%81'=>'Á','%C3%82'=>'Â','%C3%83'=>'Ã','%C3%84'=>'Ä','%C3%85'=>'Å','%C3%86'=>'Æ','%C3%87'=>'Ç','%C3%88'=>'È','%C3%89'=>'É','%C3%8A'=>'Ê','%C3%8B'=>'Ë','%C3%8C'=>'Ì','%C3%8D'=>'Í','%C3%8E'=>'Î','%C3%8F'=>'Ï','%C3%90'=>'Ð','%C3%91'=>'Ñ','%C3%92'=>'Ò','%C3%93'=>'Ó','%C3%94'=>'Ô','%C3%95'=>'Õ','%C3%96'=>'Ö','%C3%97'=>'×','%C3%98'=>'Ø','%C3%99'=>'Ù','%C3%9A'=>'Ú','%C3%9B'=>'Û','%C3%9C'=>'Ü','%C3%9D'=>'Ý','%C3%9E'=>'Þ','%C3%9F'=>'ß','%C3%A0'=>'à','%C3%A1'=>'á','%C3%A2'=>'â','%C3%A3'=>'ã','%C3%A4'=>'ä','%C3%A5'=>'å','%C3%A6'=>'æ','%C3%A7'=>'ç','%C3%A8'=>'è','%C3%A9'=>'é','%C3%AA'=>'ê','%C3%AB'=>'ë','%C3%AC'=>'ì','%C3%AD'=>'í','%C3%AE'=>'î','%C3%AF'=>'ï','%C3%B0'=>'ð','%C3%B1'=>'ñ','%C3%B2'=>'ò','%C3%B3'=>'ó','%C3%B4'=>'ô','%C3%B5'=>'õ','%C3%B6'=>'ö','%C3%B7'=>'÷','%C3%B8'=>'ø','%C3%B9'=>'ù','%C3%BA'=>'ú','%C3%BB'=>'û','%C3%BC'=>'ü','%C3%BD'=>'ý','%C3%BE'=>'þ','%C3%BF'=>'ÿ'}
URL_DECODE_MAP = URL_ENCODE_MAP.invert

def content_type(path)
  return 'text/plain' unless File.exist?(path)
  CONTENT_TYPE_MAPPING.fetch(File.extname(path), DEFAULT_CONTENT_TYPE)
end

def unserialize_query(string)
  string ? string.split("&").reduce({}) do |acc, kv|
    k, v = kv.split("=")
    acc[k] = v
    acc
  end : {}
end

def uri_decode(string)
  buffer = []
  encoded = ''
  splited_string = string.split('%')
  encoded << splited_string.shift
  splited_string.each do |char_mix|
    char = "#{buffer.pop}%#{char_mix[0..1]}"
    if encoded_char = URL_ENCODE_MAP[char]
      encoded << encoded_char
    else
      buffer << char
    end
    tail = char_mix[2..-1]
    encoded << tail if tail
  end
  encoded
end

system "mount -t tmpfs -o size=2048M tmpfs #{WEB_ROOT}"
system "rsync -a #{HDD_STORE_WEB_ROOT} #{ROOT}"

@backup_thread = Thread.new do
  loop do
    `rsync -au --recursive --delete #{WEB_ROOT} #{HDD_STORE};sleep 1`
    break if @exiting
  end
end

loop do
  socket = SERVER.accept
  begin
    Timeout.timeout(700) do
      content_length = nil
      request_headers, request_body = '', ''
      while (line = socket.gets) do
        if content_length
          byebug
        else
          if line[/^Content\-Length: (\d+)/]
            content_length = $1
          end
          break if line == EOL
        end
        request_headers << line
      end
      puts "empty message" && next if request_headers.empty?
      request_body = nil if request_body.empty?
      request_headers = request_headers.split(EOL)
      request_method, request_path, request_protocol = request_headers.shift.split(' ')
      # request_body = socket.recvmsg[0] if request_method == 'POST' && !request_body
      request_body = request_body && uri_decode(request_body).split('&').reduce({}) do |acc, el|
        k, v = el.split('=')
        acc[k] = if k[-2..-1] == '[]'
          arr = acc[k] || []
          arr.push(v) if v
          arr
        else
          v
        end
        acc
      end
      puts "#{Time.now}, #{request_method}, #{request_path}"
      request_headers = request_headers.reduce({}) do |accumulator, string|
        key, val = string.split(': ')
        accumulator[key] = val
        accumulator
      end
      request_path, query_string = request_path.split('?')
      is_index = request_path == '/'
      @params = unserialize_query(query_string).select { |key, val| val }
      @cookie = request_headers['Cookie'] || "sessionid=#{rand(1000000)}"
      sessionid = @cookie[/sessionid\=(.+?)(?:\;|$)/, 1]
      just_updated = false
      request_path = File.join(WEB_ROOT, request_path)
      request_path = File.join(request_path, DIR_INDEX) if File.directory?(request_path)
      file_content_type = content_type(request_path)
      if File.exist?(request_path)
        file = open(request_path)
        body = file.read
        if request_path[/\.out\.html$/]
          javascript = "<script type=\"text/javascript\">window.onload = function(){window.scroll(0, document.body.scrollHeight);}</script>"
          body = "<link href=\"/partials/frame_stylesheet.css\" type=\"text/css\" rel=\"stylesheet\" />\n#{javascript}\n#{body}"
        end
      else
        socket.puts "HTTP/1.1 404 Not Found"
        socket.puts "Content-Type: text/plain; Charset=#{DEFAULT_CHARSET}"
        body = "File not found"
      end
      if file_content_type[/^text\//]
        body = body.gsub(/\<\%.+?\%\>/m) do |interpolation|
          eval(interpolation[/\<\%(.+?)\%\>/m, 1], binding)
        end
        if is_index
          last_result_checksum_key = "last_result_checksum-#{sessionid}-#{query_string}"
          last_result_checksum = REDIS.get(last_result_checksum_key).to_i
          curr_result_checksum = Crc32.calculate(body, body.size, 0)
          @not_modified = curr_result_checksum == last_result_checksum
          REDIS.set(last_result_checksum_key, curr_result_checksum) if just_updated || !@not_modified
        end
      end
      if just_updated || (@not_modified && request_headers['X-RMXHR'])
        socket.puts 'HTTP/1.1 204 No Content'
      else
        socket.puts "HTTP/1.1 200 OK"
      end
      socket.puts 'Date: Thu, 14 Feb 2017 17:07:35 GMT'
      socket.puts 'Server: Yudin'
      socket.puts 'Connection: keep-alive'
      unless just_updated || (@not_modified && request_headers['X-RMXHR'])
        socket.puts "Content-Type: #{file_content_type}; Charset=#{DEFAULT_CHARSET}"
        socket.puts "Content-Length: #{body.bytesize}"
        socket.puts "Set-Cookie: #{@cookie}"
        socket.puts
        socket.print body
      end
    end
  rescue Errno::EPIPE => err
    puts err
    retry
  rescue Timeout::Error => err
    puts err
    retry
  rescue Errno::ECONNRESET => err
    puts err
    retry
  ensure
    socket.close
  end
end
