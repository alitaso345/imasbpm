require 'bundler'
require 'digest/md5'
Bundler.require

URL = 'http://dic.nicovideo.jp/a/%E3%82%A2%E3%82%A4%E3%83%89%E3%83%AB%E3%83%9E%E3%82%B9%E3%82%BF%E3%83%BC%E3%81%AE%E6%A5%BD%E6%9B%B2%E3%81%AE%E4%B8%80%E8%A6%A7'
CACHE_DIR = '.cache/'
IMAS_BPM_CACHE_DB = '.imas_bpm_cache.db'

def main
  if ENV['FETCH_AND_STORE']
    fetch_and_store
  else
    search(ARGV[0])
  end
end

def search(query)
  rows = db.execute("select * from bpm_values where title like ?;", "%#{query}%")
  puts rows.map{|r| r.join("\t") }
end

def body(url, filename)
  url = url.match(/^http/) ? url : 'http://dic.nicovideo.jp' + url.downcase
  cache_file = CACHE_DIR + Digest::MD5.new.update(filename).to_s
  if File.exists?(cache_file)
    open(cache_file).read
  else
    body = Faraday.get(url).body
    open(cache_file, 'w').write body
    body
  end
end

def fetch_and_store
  doc = Nokogiri::HTML(body(URL, 'root'))

  # CD収録楽曲のみを対象とする
  # そのテーブル番号が3
  table = doc.xpath('//table[3]')[0]
  rows = []

  table.xpath('.//tr').each do |tr|
    td = tr.xpath('.//td[1]')
    title = td.text
    
    next if td.xpath('.//a').empty? || title.match(/備考/)
    link = td.xpath('.//a')[0].attributes["href"].value

    music_doc = Nokogiri::HTML(body(link, title))

    m_tables = music_doc.xpath('//table')
    m_tables.each do |table|
      table.xpath('.//tr').each do |tr|
        # ゲームが初出の曲はtableの構成が違う
        # 例:Tulip http://dic.nicovideo.jp/a/tulip%28%E3%82%A2%E3%82%A4%E3%83%89%E3%83%AB%E3%83%9E%E3%82%B9%E3%82%BF%E3%83%BC%29
        # なのでパースするやり方を変えなければいけないのだが、ひとまずゲーム初出のやつは置いておく
        th = tr.xpath('.//th')
        next if th.text.match(/BPM/i).nil?
        bpm = tr.xpath('.//td[1]').text.to_i

        rows << [title, bpm]
      end
    end
  end

  store(rows)
end

def db
  @db ||= SQLite3::Database.new(IMAS_BPM_CACHE_DB)
end

def store(rows)
  db.execute <<-SQL
    drop table if exists bpm_values;
  SQL

  db.execute <<-SQL
    create table bpm_values (
      title text,
      bpm integer
    );
  SQL

  rows.each do |title, bpm|
    db.execute("insert into bpm_values (title, bpm) values (?, ?);", [title, bpm])
  end
end

main
