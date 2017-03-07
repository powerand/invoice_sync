$:.unshift File.dirname(__FILE__)

require 'server+geocode'
require 'typhoeus'
require 'mosmetro'

HYDRA = Typhoeus::Hydra.new(max_concurrency: 3)

def main_sql_request(market_index)
  dii = DII_SITES_INDEX.include?(market_index)
  dit = dii ? 'SO' : 'SOD'
  sodj = dii ? '' : 'LEFT JOIN b_sale_order_delivery SOD ON SOD.ORDER_ID=SO.ID '
  phi = PHI_SITES_INDEX.include?(market_index)
  cti = CTT_SITES_INDEX.include?(market_index)
  dcv = DCV_SITES_INDEX.include?(market_index)
  ctt = cti ? 'b_sale_loc_name' : 'b_sale_location_city_lang'
  cttj = %{
    LEFT JOIN b_sale_location SL ON SL.#{phi ? 'ID' : 'CODE'}=PR6.VALUE
    LEFT JOIN #{ctt} CT ON CT.#{cti ? 'LOCATION_ID' : 'CITY_ID'}=SL.CITY_ID AND CT.#{cti ? 'LANGUAGE_ID' : 'LID'}='ru'
  }
  return %{
    SELECT
    CONCAT_WS(', ',
      COALESCE(substring_index(PR5.VALUE, ',', 1), #{dcv ? 'COALESCE(CT.NAME, DC.DEFAULT_VALUE)' : 'CT.NAME'}),
      COALESCE(PR7.VALUE, CONCAT_WS(', ', PR8.VALUE, PR9.VALUE, PR10.VALUE))
    ) ADDRESS
    FROM b_sale_order SO
    #{sodj}
    LEFT JOIN b_sale_order_props DC ON DC.NAME='Город'
    LEFT JOIN b_sale_order_props_value PR5 ON PR5.ORDER_ID=SO.ID AND PR5.NAME='Город'
    LEFT JOIN b_sale_order_props_value PR6 ON PR6.ORDER_ID=SO.ID AND PR6.NAME='Местоположение'
    LEFT JOIN b_sale_order_props_value PR7 ON PR7.ORDER_ID=SO.ID AND PR7.NAME='Адрес доставки'
    LEFT JOIN b_sale_order_props_value PR8 ON PR8.ORDER_ID=SO.ID AND PR8.NAME='Улица'
    LEFT JOIN b_sale_order_props_value PR9 ON PR9.ORDER_ID=SO.ID AND PR9.NAME='Дом'
    LEFT JOIN b_sale_order_props_value PR10 ON PR10.ORDER_ID=SO.ID AND PR10.NAME='Корпус/строение'
    #{cttj}
    ORDER BY #{dit}.DELIVERY_DOC_DATE DESC
  }
end
@result = Parallel.map(MARKET_NAMES, progress: "обработка") do |market_name|
  market_index = MARKET_NAMES.index(market_name)
  child_start_time = Time.now
  child_res = MYSQL_CLIENTS[market_index].query(main_sql_request(market_index)).to_a
  puts "на #{market_name} потратил #{Time.now - child_start_time}"
  child_res
end.reduce(&:+).map do |element|
  adr = element['ADDRESS']
  mad = adr.gsub("\r\n", ", ")
  mad = mad.gsub(/\b(?:подъезд|подезд|под|п|квартира|кв|этаж|эт|э|оф)\.?\s*\d+[\,\s\;]*/i, '')
  mad = mad.gsub(/\b\d+\s*\b(?:подъезд|подезд|под|п|квартира|кв|этаж|эт|э|оф)\.?[\,\s\;]*/i, '')
  mad = mad.gsub(/\bтел.*\+?[78][\s\-\(]?\d{3}[\s\-\)]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}[\,\s\;]*/i, '')
  mad = mad.gsub(/\b(?:код домофона|домофон|код двери|домовой|дмф|код|д\/ф)\.?\s*\d+.?(?:ключ|к)?.?\d+/i, '')
  mad = mad.gsub(/\b(?:понедельник|вторник|среда|четверг|пятница|суббота|воскресенье)\s*\d{1,2}[\.:]\d{2}/, '')
  uri = "https://geocode-maps.yandex.ru/1.x/?format=json&geocode=#{CGI.escape(mad)}"
  next if (buf = REDIS.get('METRO_' + adr)) && buf != '-'
  if mad && !mad.empty?
    req = Typhoeus::Request.new(uri)
    HYDRA.queue(req)
    [adr, mad, req]
  else
    REDIS.set('METRO_' + adr, '-1-')
    next
  end
end

HYDRA.run

@result.each do |adr, mad, req|
  begin
    next unless req && adr && mad
    res = JSON.parse(req.response.body)
    err = res['error']
    goc = res['response']['GeoObjectCollection']
    met = goc['metaDataProperty']['GeocoderResponseMetaData']
    siz = met['found'].to_i
    if siz == 0
      REDIS.set('METRO_' + adr, '-3-')
      next
    end
    unless goc['featureMember']
      REDIS.set('METRO_' + adr, '-4-')
      next
    end
    sug = met['suggest']
    puts "  больше 1-го результатов по запросу #{mad} количество #{siz} оригинал #{adr}" if siz > 1
    mem = goc['featureMember'][0]['GeoObject']
    lat, lng = mem['Point']['pos'].split(' ').map(&:to_f).reverse
    ugr = ST_NAM.each_with_index.min_by do |st_nam, i|
      (ST_LAT[i] - lat).abs + (ST_LNG[i] - lng).abs
    end[0]
    puts "запрос #{mad} ответ #{ugr}"
    REDIS.set('METRO_' + adr, ugr)
  rescue => ems
    raise err['message'] if err && err['status'] == '429'
    byebug
    retry
  end
end
