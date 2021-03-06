require 'rufus-scheduler'
require 'data_mapper'
require 'rss'
require 'mechanize'
require 'logger'
require 'dm-validations'
require 'addressable'

MYDIR = File.expand_path(File.dirname(__FILE__))
DataMapper.setup(:default, "sqlite3://#{MYDIR}/database.db")
class Article
	include DataMapper::Resource
	property :id, Serial
	property :feed, URI
	property :url, URI
	property :cyber_count, Integer
	validates_uniqueness_of :url
end
DataMapper.finalize

def get_cyber url
	max = 0
	@mechanize.get(url).at('body').traverse do |node|
		text = node.text
		text = text.encode("UTF-8", :invalid=>:replace, :replace=>"?") unless text.valid_encoding?
		cyber = text.scan(/cyber/i).count
		if node.name != 'body' and cyber > max
			max = cyber
		end
	end
	return max
end

@mechanize = Mechanize.new
scheduler = Rufus::Scheduler.new
feeds = YAML.load_file("#{MYDIR}/feeds.yml")
@logger = Logger.new("#{MYDIR}/usage.log")
@logger.datetime_format = "%d/%m/%y %H:%M:%S %z "

@logger.info 'Job started. Checking for new articles.'
count = Article.count
feeds.each do |feed|
	begin
	RSS::Parser.parse(@mechanize.get(feed).content, false).items.each do |item|
		begin
		link = case item
				 when RSS::Atom::Feed::Entry then item.link.href
				 else
					 item.link
				 end
		Article.create(:url => Addressable::URI.parse(link), :cyber_count => get_cyber(link), :feed => Addressable::URI.parse(feed))
		rescue => e
			@logger.error "encountered an error when processing article #{link} #{e}"
		end
	end
	rescue => e
		@logger.error "encountered an error while processing #{feed} #{e}"
	end
end
@logger.info "Job ended. Added #{Article.count - count} new articles to the database."
