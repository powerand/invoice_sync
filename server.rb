$:.unshift File.dirname(__FILE__)

require 'socket'
require 'crc32'
require 'timeout'
require 'date'
require 'unicode'
require 'server+geocode'

def ramdisk_mounted
  !`mount|grep public`.empty?
end

Signal.trap("INT") do
  puts "exiting"
  @exiting = 1
  @backup_thread.join
  # system "umount #{WEB_ROOT}"
  if `ps aux | grep -v grep | grep ruby | grep server`.empty?
    `kill $(ps aux | grep -v grep | grep ssh | grep '127.0.0.1:3306' | awk '{print $2}')`
  end
  exit
end

SERVER = TCPServer.new PORT

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
PAY_REPLACE_TABLE = {
  'НАЛИЧНЫЙ РАСЧЕТ' => 'наличными', 'КВИТАНЦИЯ СБЕРБАНКА' => 'через сбербанк', 'МОБИЛЬНЫЙ ТЕРМИНАЛ' => 'моб. терминал',
  'ОНЛАЙН ОПЛАТА БАНКОВСКОЙ КАРТОЙ' => 'картой на сайте', 'Оплата наличными' => 'наличными', 'Сбербанк' => 'через сбербанк', 'Банковский перевод' => 'банковский перевод',
  'Мобильный терминал' => 'моб. терминал', 'Картой на сайте' => 'картой на сайте', 'Наличные' => 'наличными', 'Кредитной картой онлайн' => 'картой на сайте',
  'Наличные курьеру' => 'наличными', 'Банковской картой курьеру' => 'моб. терминал', 'Банковские карты' => 'моб. терминал'
}

def content_type(path)
  return 'text/plain' unless File.exist?(path)
  CONTENT_TYPE_MAPPING.fetch(File.extname(path), DEFAULT_CONTENT_TYPE)
end

def unserialize_query(string)
  string ? CGI.unescape(string).split("&").reduce({}) do |acc, kv|
    k, v = kv.split("=")
    if k[/^(.+)\[\]$/]
      acc[$1] ||= []
      acc[$1] << v
    else
      acc[k] = v
    end
    acc
  end : {}
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
    Timeout.timeout(60) do
      request_method, request_headers, request_body = nil, {}, ''
      while (line = socket.gets) do
        unless request_method
          request_method, request_path, request_protocol = line.split(' ', 3)
          next
        end
        line = line.split(' ', 2)
        break if line[0] == ""
        request_headers[line[0].chop] = line[1].strip
      end
      request_body = socket.read(request_headers["Content-Length"].to_i)
      puts "empty message" && next if request_headers.empty?
      puts "#{Time.now}, #{request_method}, #{request_path}, #{socket.remote_address.inspect}"
      request_path, query_string = request_path.split('?')
      original_request_path = request_path
      $params = unserialize_query(query_string).select { |key, val| val }
      request_body = nil if request_body.empty?
      $params.merge!(unserialize_query(request_body))
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
          begin
            interpolation_body = interpolation[/\<\%(.+?)\%\>/m, 1]
            eval(interpolation_body, binding)
          rescue => err
            ENVIRONTMENT == 'development' ? byebug : puts(err, err.backtrace.map { |l| "\t#{l}" }, interpolation_body)
          end
        end
        last_result_checksum_key = "last_result_checksum-#{sessionid}-#{PORT}-#{original_request_path}-#{query_string}"
        last_result_checksum = REDIS.get(last_result_checksum_key).to_i
        curr_result_checksum = Crc32.calculate(body, body.size, 0)
        @not_modified = curr_result_checksum == last_result_checksum
        REDIS.set(last_result_checksum_key, curr_result_checksum) if just_updated || !@not_modified
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
  rescue Timeout::Error => err
    puts err
  rescue Errno::ECONNRESET => err
    puts err
  ensure
    socket.close
  end
end
