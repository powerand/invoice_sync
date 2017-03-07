DEL_REPLACE_TABLE = {
  'Доставка до транспортной компании в Москве' => 'до ТК', 'Доставка курьером (400 руб.)' => 'курьером', 'Самовывоз' => 'самовывоз', 'Доставка курьером' => 'курьером',
  'Бесплатная доставка курьером' => 'курьером', 'Бесплатная доставка до любой транспортной компании в Москве' => 'до ТК',
  'Доставка до любой транспортной компании в Москве (400 руб.)' => 'до ТК', 'Без доставки' => 'самовывоз', 'Почта России' => 'почтой России'
}
DTT_SITES_INDEX = [2, 3, 4]
class Incoming
  attr_accessor :result, :date_from, :date_to, :date_subject, :requisites

  def main_sql_request(market_index)
    dii = DII_SITES_INDEX.include?(market_index)
    dit = dii ? 'SO' : 'SOD'
    dis = (@date_subject == 'created') ? "DATE(SO.DATE_INSERT)" : "#{dit}.DELIVERY_DOC_DATE"
    dtt = DTT_SITES_INDEX.include?(market_index) ? 'b_sale_delivery_srv' : 'b_sale_delivery'
    cti = CTT_SITES_INDEX.include?(market_index)
    phi = PHI_SITES_INDEX.include?(market_index)
    dcv = DCV_SITES_INDEX.include?(market_index)
    nps = NPS_SITES_INDEX.include?(market_index)
    ctt = cti ? 'b_sale_loc_name' : 'b_sale_location_city_lang'
    cttj = %{
      LEFT JOIN b_sale_location SL ON SL.#{phi ? 'ID' : 'CODE'}=PR6.VALUE
      LEFT JOIN #{ctt} CT ON CT.#{cti ? 'LOCATION_ID' : 'CITY_ID'}=SL.CITY_ID AND CT.#{cti ? 'LANGUAGE_ID' : 'LID'}='ru'
    }
    sodj = 'LEFT JOIN b_sale_order_delivery SOD ON SOD.ORDER_ID=SO.ID' unless dii
    xpsj = nps ? 'LEFT JOIN b_sale_pay_system PS ON PS.ID=SO.PAY_SYSTEM_ID' : 'LEFT JOIN b_sale_order_payment SOP ON SOP.ORDER_ID=SO.ID'
    date_fr_rstr = %{ AND #{dis}>="#{@date_from}"} if @date_from
    date_to_rstr = %{ AND #{dis}<="#{@date_to}"} if @date_to
    return %{
      SELECT
        SO.ID,
        DATE_FORMAT(SO.DATE_INSERT, '%Y-%m-%d %T') DATE,
        DATE(#{dit}.DELIVERY_DOC_DATE) DELIVERY_DATE,
        '#{MARKET_NAMES[market_index]}' SITE,
        PR1.VALUE FIO,
        COALESCE(substring_index(PR5.VALUE, ',', 1), #{dcv ? 'COALESCE(CT.NAME, DC.DEFAULT_VALUE)' : 'CT.NAME'}) CITY,
        COALESCE(PR7.VALUE, CONCAT_WS(', ', CONCAT('ул. ', PR8.VALUE), CONCAT('дом ', PR9.VALUE), CONCAT('к.', PR10.VALUE), CONCAT('кв. ', PR11.VALUE))) ADDRESS,
        CONCAT_WS(', ',
          COALESCE(substring_index(PR5.VALUE, ',', 1), #{dcv ? 'COALESCE(CT.NAME, DC.DEFAULT_VALUE)' : 'CT.NAME'}),
          COALESCE(PR7.VALUE, CONCAT_WS(', ', PR8.VALUE, PR9.VALUE, PR10.VALUE))
        ) ADDR,
        SD.NAME DELIVERY,
        FLOOR(SO.PRICE_DELIVERY) DELIVERY_PRICE,
        #{nps ? 'PS.NAME' : 'SOP.PAY_SYSTEM_NAME'} PAYMENT,
        FLOOR(SO.PRICE) PRICE
      FROM b_sale_order SO
      #{sodj}
      LEFT JOIN b_sale_order_props DC ON DC.NAME='Город'
      LEFT JOIN b_sale_order_props_value PR1 ON PR1.ORDER_ID=SO.ID AND PR1.NAME='Ф.И.О.'
      LEFT JOIN b_sale_order_props_value PR5 ON PR5.ORDER_ID=SO.ID AND PR5.NAME='Город'
      LEFT JOIN b_sale_order_props_value PR6 ON PR6.ORDER_ID=SO.ID AND PR6.NAME='Местоположение'
      LEFT JOIN b_sale_order_props_value PR7 ON PR7.ORDER_ID=SO.ID AND PR7.NAME='Адрес доставки'
      LEFT JOIN b_sale_order_props_value PR8 ON PR8.ORDER_ID=SO.ID AND PR8.NAME='Улица'
      LEFT JOIN b_sale_order_props_value PR9 ON PR9.ORDER_ID=SO.ID AND PR9.NAME='Дом'
      LEFT JOIN b_sale_order_props_value PR10 ON PR10.ORDER_ID=SO.ID AND PR10.NAME='Корпус/строение'
      LEFT JOIN b_sale_order_props_value PR11 ON PR11.ORDER_ID=SO.ID AND PR11.NAME='Квартира'
      #{cttj}
      LEFT JOIN #{dtt} SD ON SD.ID=#{dit}.DELIVERY_ID
      #{xpsj}
      WHERE 1=1#{date_fr_rstr}#{date_to_rstr}
    }
  end

  def run
    start_time = Time.now
    @date_from = $params['from'] || Date.today.strftime("%Y-%m-%d")
    @date_to = $params['to']
    @date_subject = $params['date_subject'] || 'created'
    @result = Parallel.map(MARKET_NAMES) do |market_name|
      market_index = MARKET_NAMES.index(market_name)
      # child_start_time = Time.now
      child_res = MYSQL_CLIENTS[market_index].query(main_sql_request(market_index)).to_a
      # puts "на #{market_name} потратил #{Time.now - child_start_time}"
      child_res
    end.reduce(&:+).inject({}) do |hash, element|
      if element['ID']
        key = element['ID'].to_s + DELIMIER + element['SITE']
        element['DELIVERY'] = DEL_REPLACE_TABLE[element['DELIVERY']] || element['DELIVERY']
        element['DELIVERY'] && element['DELIVERY'] != 'самовывоз' && element['DELIVERY'] += ', ' + element['DELIVERY_PRICE'].to_s
        element['PAYMENT'] = PAY_REPLACE_TABLE[element['PAYMENT']] || element['PAYMENT']
        hash[key] ||= {}
        hash[key]['ID'] ||= element['ID']
        hash[key]['DATE'] ||= element['DATE']
        hash[key]['DELIVERY_DATE'] ||= element['DELIVERY_DATE']
        hash[key]['SITE'] ||= element['SITE']
        hash[key]['FIO'] ||= element['FIO']
        hash[key]['CITY'] ||= element['CITY']
        hash[key]['ADDRESS'] ||= element['ADDRESS']
        hash[key]['METRO'] ||= REDIS.get('METRO_' + element['ADDR'])
        hash[key]['DELIVERY'] ||= element['DELIVERY']
        hash[key]['PAYMENT'] ||= element['PAYMENT']
        hash[key]['PRICE'] ||= element['PRICE']
      end
      hash
    end.sort_by do |_, value|
      value['ID']
    end.sort_by do |_, value|
      value['SITE']
    end.to_h.to_json
    @requisites = '[' + REDIS.smembers('requisites').join(',').gsub('=>', ':').gsub('nil', 'null') + ']'
    puts "master процесс потратил #{Time.now - start_time}"
  end
end