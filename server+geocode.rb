require 'byebug'
require 'parallel'
require 'ruby-progressbar'
require 'redis'
require 'mysql2'
require 'json'

PART_NUMS = %w(0 1 2 3)
ROOT = File.dirname(File.expand_path(__FILE__))
WEB_ROOT = File.join(ROOT, 'public')
HDD_STORE = File.join(ROOT, 'hdd-store')
HDD_STORE_WEB_ROOT = File.join(HDD_STORE, 'public')
REDIS = Redis.new(path: '/tmp/redis.sock')
THREADS = []
ARGV_OPTIONS = ARGV.reduce({}) do |acc, arg|
  arg = (arg[0..1] == '--' ? arg[2..-1] : arg).split('=')
  acc[arg[0]] = arg[1] || true
  acc
end
PORT = ARGV_OPTIONS['port'] ? ARGV_OPTIONS['port'].to_i : 81
DEBUG = ARGV_OPTIONS['debug']
MARKET_NAMES = ['vselampi', 'funale', 'fener', 'ojax', 'allmar']
ENVIRONTMENT = ARGV_OPTIONS['environtment'] || 'development'
LINUX_USER = 'root'
LINUX_HOST = ['vselampi.ru', 'funale.ru', 'fener.ru', 'ojax.ru', 'allmar.ru']
MYSQL_USER = ['vselampi', 'funaleyi_funale', 'shavo2c5_ss', 'aaa77mxp_new', 'root']
MYSQL_PASSWORD = ['uRDIsPpv', '8YtSdf75sig55X5413s9vgh1d7dEb2432', '24?Ep{Et', 'G6F2SdfR78Us2XKuO', '8YtSdf75sig55X5413s9vgh1d7dEb2432']
MYSQL_DB = ['vselampi_new', 'funaleyi_funale', 'shavo2c5_ss', 'aaa77mxp_new', 'all-mark']
MYSQL_CLIENTS = []
DELIMIER = '->|<-'
DII_SITES_INDEX = [0, 1]
PHI_SITES_INDEX = [0]
CTT_SITES_INDEX = [3, 4]
DCV_SITES_INDEX = [1]
NPS_SITES_INDEX = [0, 1]

MARKET_NAMES.each do |market_name|
  market_index = MARKET_NAMES.index(market_name)
  port = `ps aux | grep -v grep | grep ssh | grep '127.0.0.1:3306' | grep '#{market_name}' | awk '{print $15}' | cut -d':' -f 1`.chomp
  if port.empty?
    tmpserv = TCPServer.new('127.0.0.1', 0)
    port = tmpserv.addr[1]
    tmpserv.close
    system "ssh -f -N -L #{port}:127.0.0.1:3306 #{LINUX_USER}@#{LINUX_HOST[market_index]}"
  end
  MYSQL_CLIENTS[market_index] = Mysql2::Client.new(
    host: "127.0.0.1",
    username: MYSQL_USER[market_index],
    password: MYSQL_PASSWORD[market_index],
    database: MYSQL_DB[market_index],
    port: port
  )
  MYSQL_CLIENTS[market_index].automatic_close = false
end
