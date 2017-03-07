require 'ru_propisju'

class PrintOrder
  attr_accessor :result

  def plur(int)
    'один'
  end

  def main_sql_request(market_index)
    kvs = $params["id"].inject({}) do |hash, element|
      k, v = element.split('_')
      hash[k] = v
      hash
    end
    ids = kvs.select { |k, v| v == MARKET_NAMES[market_index] }.keys
    ids = ids.empty? ? '0' : ids.join(',')
    dcv = DCV_SITES_INDEX.include?(market_index)
    phi = PHI_SITES_INDEX.include?(market_index)
    cti = CTT_SITES_INDEX.include?(market_index)
    nps = NPS_SITES_INDEX.include?(market_index)
    idt = DTT_SITES_INDEX.include?(market_index)
    diiisot = DII_SITES_INDEX.include?(market_index)
    ctt = cti ? 'b_sale_loc_name' : 'b_sale_location_city_lang'
    dtt = idt ? 'b_sale_delivery_srv' : 'b_sale_delivery'
    dit = diiisot ? 'SO' : 'SOD'
    sod_join = diiisot ? '' : 'LEFT JOIN b_sale_order_delivery SOD ON SOD.ORDER_ID=SO.ID '
    xpsj = nps ? 'LEFT JOIN b_sale_pay_system PS ON PS.ID=SO.PAY_SYSTEM_ID' : 'LEFT JOIN b_sale_order_payment SOP ON SOP.ORDER_ID=SO.ID'
    cttj = %{
      LEFT JOIN b_sale_location SL ON SL.#{phi ? 'ID' : 'CODE'}=PR6.VALUE
      LEFT JOIN #{ctt} CT ON CT.#{cti ? 'LOCATION_ID' : 'CITY_ID'}=SL.CITY_ID AND CT.#{cti ? 'LANGUAGE_ID' : 'LID'}='ru'
    }
    nsm = %{SUBSTRING_INDEX(SUBSTRING_INDEX(SUBSTRING_INDEX(SD.CONFIG, 'PRICE";s:', -1), '"', 2), '"', -1)}
    return %{
      SELECT
        SO.ID,
        '#{MARKET_NAMES[market_index]}' SITE,
        PR1.VALUE FIO,
        SB.NAME PRODUCT_NAME,
        FLOOR(SB.QUANTITY) PRODUCT_QUANTITY,
        SB.PRICE PRODUCT_PRICE,
        DATE_FORMAT(SO.DATE_INSERT, '%d.%m.%Y') DATE,
        DATE_FORMAT(#{dit}.DELIVERY_DOC_DATE, '%d.%m.%Y') DELIVERY_DOC_DATE,
        COALESCE(substring_index(PR5.VALUE, ',', 1), #{dcv ? 'COALESCE(CT.NAME, DC.DEFAULT_VALUE)' : 'CT.NAME'}) CITY,
        COALESCE(PR7.VALUE, CONCAT_WS(', ', CONCAT('ул. ', PR8.VALUE), CONCAT('дом ', PR9.VALUE), CONCAT('к.', PR10.VALUE), CONCAT('кв. ', PR11.VALUE))) ADDRESS,
        PR12.VALUE PHONE,
        #{nps ? 'PS.NAME' : 'SOP.PAY_SYSTEM_NAME'} PAYMENT,
        FORMAT(FLOOR(#{idt ? nsm : 'SD.PRICE'}), 0) PRICE_DELIVERY,
        SO.DELIVERY_DOC_NUM DELIVERY_DOC_NUM
      FROM b_sale_basket SB
      LEFT JOIN b_sale_order SO ON SB.ORDER_ID=SO.ID
      LEFT JOIN b_sale_order_props DC ON DC.NAME='Город' AND DC.PROPS_GROUP_ID=2
      LEFT JOIN b_sale_order_props_value PR1 ON PR1.ORDER_ID=SO.ID AND PR1.NAME='Ф.И.О.'
      LEFT JOIN b_sale_order_props_value PR5 ON PR5.ORDER_ID=SO.ID AND PR5.NAME='Город'
      LEFT JOIN b_sale_order_props_value PR6 ON PR6.ORDER_ID=SO.ID AND PR6.NAME='Местоположение'
      LEFT JOIN b_sale_order_props_value PR7 ON PR7.ORDER_ID=SO.ID AND PR7.NAME='Адрес доставки'
      LEFT JOIN b_sale_order_props_value PR8 ON PR8.ORDER_ID=SO.ID AND PR8.NAME='Улица'
      LEFT JOIN b_sale_order_props_value PR9 ON PR9.ORDER_ID=SO.ID AND PR9.NAME='Дом'
      LEFT JOIN b_sale_order_props_value PR10 ON PR10.ORDER_ID=SO.ID AND PR10.NAME='Корпус/строение'
      LEFT JOIN b_sale_order_props_value PR11 ON PR11.ORDER_ID=SO.ID AND PR11.NAME='Квартира'
      LEFT JOIN b_sale_order_props_value PR12 ON PR12.ORDER_ID=SO.ID AND PR12.NAME='Телефон'
      #{cttj}
      #{sod_join}
      #{xpsj}
      LEFT JOIN #{dtt} SD ON SD.NAME='Доставка курьером'
      WHERE SO.ID IN (#{ids}) AND #{dit}.DELIVERY_DOC_DATE IS NOT NULL
    }
  end

  def run
    start_time = Time.now
    @result = Parallel.map(MARKET_NAMES) do |market_name|
      market_index = MARKET_NAMES.index(market_name)
      # child_start_time = Time.now
      child_res = MYSQL_CLIENTS[market_index].query(main_sql_request(market_index)).to_a
      # puts "на #{market_name} потратил #{Time.now - child_start_time}"
      child_res
    end.reduce(&:+).inject({}) do |hash, element|
      element['PAYMENT'] = PAY_REPLACE_TABLE[element['PAYMENT']] || element['PAYMENT']
      key = element['ID'].to_s + DELIMIER + element['SITE']
      hash[key] ||= {}
      hash[key]['FIO'] ||= element['FIO']
      hash[key]['ID'] ||= element['ID'].to_s
      hash[key]['SITE'] ||= element['SITE']
      hash[key]['DATE'] ||= element['DATE']
      hash[key]['DELIVERY_DOC_DATE'] ||= element['DELIVERY_DOC_DATE']
      hash[key]['CITY'] ||= element['CITY']
      hash[key]['ADDRESS'] ||= element['ADDRESS']
      hash[key]['PHONE'] ||= element['PHONE']
      hash[key]['PAYMENT'] ||= element['PAYMENT']
      hash[key]['PRICE_DELIVERY'] ||= element['PRICE_DELIVERY']
      hash[key]['DELIVERY_DOC_NUM'] ||= element['DELIVERY_DOC_NUM']
      hash[key]['PRODUCT_NAMES'] ||= []
      hash[key]['PRODUCT_NAMES'] << element['PRODUCT_NAME']
      hash[key]['PRODUCT_QUANTITYS'] ||= []
      hash[key]['PRODUCT_QUANTITYS'] << element['PRODUCT_QUANTITY']
      hash[key]['PRODUCT_PRICES'] ||= []
      hash[key]['PRODUCT_PRICES'] << element['PRODUCT_PRICE'].to_f
      hash
    end.to_h
    puts "master процесс потратил #{Time.now - start_time}"
  end
end