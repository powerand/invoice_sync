class Requisites
  attr_accessor :result

  def run
    @result = '[' + REDIS.smembers('requisites').join(',').gsub('=>', ':').gsub('nil', 'null') + ']'
  end
end