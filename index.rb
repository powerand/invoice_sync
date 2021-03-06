#!/usr/local/bin/ruby

FLAG_UKEYS = ['PRODUCT_ID', 'SITE', 'ORDER_ID']
PROP_NAMES = [
  ['Артикул[Основные характеристики]', 'Бренд[Основные характеристики]'],
  nil,
  ['Артикул[Основные характеристики]', 'Бренд[Основные характеристики]'],
]
DEFAULT_PROP_NAMES = ['Артикул', 'Бренд']

class Outgoing
  attr_accessor :result, :date_from, :date_to

  def main_sql_request(market_index)
    iblock_ids = MYSQL_CLIENTS[market_index].query("SELECT ID FROM b_iblock WHERE IBLOCK_TYPE_ID LIKE '%catalog%' AND ACTIVE = 'Y'").to_a.map{|e| e['ID']}
    select_props = []
    ['articule', 'brand'].each_with_index do |subject, idx|
      market_prop_names = PROP_NAMES[market_index] || DEFAULT_PROP_NAMES
      subject_ids = MYSQL_CLIENTS[market_index].query(%{
        SELECT ID FROM b_iblock_property WHERE IBLOCK_ID IN (#{iblock_ids.join(',')}) AND NAME='#{market_prop_names[idx]}'
      }).to_a.map{|e| e['ID']}
      subject_scl = iblock_ids.each_with_index.map do |iblock_id, idx|
        subject_id = subject_ids[idx]
        puts %{SELECT ID FROM b_iblock_property WHERE IBLOCK_ID IN (#{iblock_ids.join(',')}) AND NAME='#{market_prop_names[idx]}'} unless subject_id # tmp
        "IEPS#{iblock_id}.PROPERTY_#{subject_id}"
      end.join(',')
      select_props << "COALESCE(#{subject_scl}) #{subject.upcase}"
    end
    prop_joins = iblock_ids.map do |iblock_id|
      "LEFT JOIN b_iblock_element_prop_s#{iblock_id} IEPS#{iblock_id} ON IEPS#{iblock_id}.IBLOCK_ELEMENT_ID=SB.PRODUCT_ID "
    end.join
    diiisot = DII_SITES_INDEX.include?(market_index)
    dit = diiisot ? 'SO' : 'SOD'
    sod_join = diiisot ? '' : 'LEFT JOIN b_sale_order_delivery SOD ON SOD.ORDER_ID=SO.ID '
    date_fr_rstr = %{ AND #{dit}.DELIVERY_DOC_DATE>="#{@date_from}"} if @date_from
    date_to_rstr = %{ AND #{dit}.DELIVERY_DOC_DATE<="#{@date_to}"} if @date_to
    return %{
      SELECT IE.NAME, #{dit}.DELIVERY_DOC_DATE, #{select_props.join(',')}, FLOOR(SB.PRICE) PRICE, SB.QUANTITY, '#{MARKET_NAMES[market_index]}' SITE, SB.ORDER_ID, SB.PRODUCT_ID
      FROM b_sale_order SO #{sod_join}LEFT JOIN b_sale_basket SB ON SB.ORDER_ID=SO.ID
      LEFT JOIN b_iblock_element IE ON IE.ID=SB.PRODUCT_ID
      #{prop_joins}
      WHERE #{dit}.ALLOW_DELIVERY="Y"#{date_fr_rstr}#{date_to_rstr}
    }
  end

  def run
    start_time = Time.now
    @date_from = $params['from'] || Date.today.strftime("%Y-%m-%d")
    @date_to = $params['to']
    @result = Parallel.map(MARKET_NAMES) do |market_name|
      market_index = MARKET_NAMES.index(market_name)
      # child_start_time = Time.now
      child_res = MYSQL_CLIENTS[market_index].query(main_sql_request(market_index)).to_a
      # puts "на #{market_name} потратил #{Time.now - child_start_time}"
      child_res
    end.reduce(&:+).inject({}) do |hash, element|
      if element['ARTICULE'] && element['BRAND']
        key = Unicode.downcase(element['ARTICULE'] + DELIMIER + element['BRAND'])
        hash[key] ||= {}
        hash[key]['ARTICULE'] ||= element['ARTICULE']
        hash[key]['BRAND'] ||= element['BRAND']
        hash[key]['NAME'] ||= element['NAME']
        hash[key]['QUANTITYS'] ||= []
        hash[key]['QUANTITYS'] << element['QUANTITY'].to_i
        hash[key]['SITES'] ||= []
        hash[key]['SITES'] << element['SITE']
        hash[key]['ORDERS'] ||= []
        hash[key]['ORDERS'] << element['ORDER_ID']
        hash[key]['PRODUCTS'] ||= []
        hash[key]['PRODUCTS'] << element['PRODUCT_ID']
        hash[key]['DELIVERY_DOC_DATES'] ||= []
        hash[key]['DELIVERY_DOC_DATES'] << element['DELIVERY_DOC_DATE'].strftime("%F")
        hash[key]['COMMENTS'] ||= []
        new_comment = REDIS.get((FLAG_UKEYS.map { |ukey| element[ukey].to_s } + ['0']).join(';%20'))
        hash[key]['COMMENTS'] << new_comment unless hash[key]['COMMENTS'].include?(new_comment)
        hash[key]['PRICES'] ||= []
        hash[key]['PRICES'] << element['PRICE']
        3.times.each do |i|
          i += 1
          hash[key]["ST#{i}"] ||= 0
          hash[key]["ST#{i}"] += REDIS.get((FLAG_UKEYS.map { |ukey| element[ukey].to_s } + [i.to_s]).join(';%20')).to_i
        end
      end
      hash
    end.sort_by do |_, value|
      value['ST2']
    end.sort_by do |_, value|
      Unicode.downcase(value['BRAND'])
    end.to_h.to_json
    puts "master процесс потратил #{Time.now - start_time}"
  end
end
