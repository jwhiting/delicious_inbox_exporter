# Please see README for introductory information.
#
# OUTPUT CONFIGURATION
# ====================
# 
# These defaults will work fine, but they are here for you to change according
# to your preferences.

add_tags = 'inbox'              # these tags will be added to every inbox item
                                # (space-separated)

mark_private = true             # items will be marked private, using a
                                # PRIVATE="1" attribute in the anchor tag

description_sender = true       # the description (aka "notes") will be
                                # appended with the sender according to
                                # description_sender_format

description_sender_format = "[from %PROFILENAME%]"
                                # %PROFILENAME% will be replaced with the
                                # user's profile name. %USERNAME% will be
                                # replaced with the user name. in many
                                # cases these are the same value, if the
                                # sending user has not setup a profile name in
                                # their delicious account settings

tag_sender = true               # add a tag for the sending user according to
                                # tag_sender_format

tag_sender_format = "from:delicious/%USERNAME%"
                                # %USERNAME% will be replaced with the
                                # delicious username. note that %PROFILENAME%
                                # is not supported in this case.

page_request_delay = 500        # how many milliseconds to wait between page
                                # loads, to be nice on Yahoo's servers.

# END CONFIGURATION



require 'net/http'
require 'uri'
require 'rubygems'
require 'hpricot'
require 'cgi'
require 'time'

puts "
This script does not automate the login process. You need to login to Delicious
and then copy/paste your authenticated site cookies here. Although strange,
it's plenty secure and really quite easy:

1. Sign in to Delicious

2. Go to your inbox page to make sure you see your inbox items

3. In the browser's address bar, enter this string verbatim and hit return:

   javascript:alert(document.cookie)

   This will pop up an alert with the contents of your cookies for the
   delicious.com domain.

4. Copy the entire blurb from the alert box and paste it here

Note: this data will be discarded when the script completes for your security

Please paste the cookie blurb now, and hit return:

"

cookie = ''
while (cookie.empty?) do
  cookie << STDIN.gets
  cookie.gsub!(/\A\s+|\s+\Z/,'')
end
puts ""

# I've chosen to be a good citizen and present a custom user agent
user_agent = "Delicious Inbox Exporter v0.1"

# get delicious username from cookie
if (cookie =~ /.*_user=([a-zA-Z90-9\_\.]+).*/)
  username = $1
  puts "Exporting inbox for delicious/#{username}"
else
  puts "Could not get your delicious username from the cookie data. "+
       "Please check that you've followed the cookie instructions."
  exit
end

# open output file
out_fn = $ARGV[0]
unless out_fn.to_s.length > 0
  puts "Please specify an output file as the first argument"
  exit
end
outfile = File.open(out_fn,"w") rescue nil
unless outfile
  outs "Could not open output file '#{out_fn}' for writing."
  exit
end

# setup scraper loop
items = []
page = 1
morepages = true
while (morepages) do

  puts "Fetching and parsing inbox page #{page}..."
  url = URI.parse("http://www.delicious.com/inbox/#{username}?page=#{page}&setcount=100")
  path = url.path + (url.query ? "?"+url.query : "")
  req = Net::HTTP::Get.new(path)
  req["User-Agent"] = user_agent
  req["Cookie"] = cookie
  http = Net::HTTP.new(url.host, url.port)
  res = http.start {|http|
    http.request(req)
  }
  doc = Hpricot.parse(res.body)

  # let the scraping begin
  page_items = []
  date_group = nil
  doc.search("li").each { |li|
    if li.classes.include? "post"
      item = {
        :tags => [],
        :description => '',
        :url => nil,
        :title => nil,
        :from_user_name => nil,
        :from_user_profile_name => nil,
        :date => nil,
      }
      li.search("div[@class~='dateGroup']").each do |d|
        date_group = d.attributes['title']
      end
      item[:date] = date_group
      li.search("a").each do |a|
        if a.classes.include? "taggedlink"
          item[:url] = a.attributes['href']
          item[:title] = a.inner_text
        end
        if a.classes.include? "user"
          item[:from_user_name] = a.attributes['href'].gsub(/^\//,'') 
          item[:from_user_profile_name] = a.inner_text
        end
        if a.classes.include? "tag"
          item[:tags] << a.inner_text.gsub(/\A\s+|\s+\Z/,'')
        end
      end
      li.search("div[@class~='description']").each do |d|
        item[:description] = d.inner_text.gsub(/\A\s+|\s+\Z/,'')
      end
      page_items << item
    end
  }
  items.concat(page_items)
  puts "Got #{page_items.length} items from page #{page} (#{items.length} total so far)"

  # check pagination div to see if there's a "next" element
  morepages = false
  doc.search("div[@id~='pagination']").each do |d|
    d.search("a[@class~='next']").each do |a|
      morepages = true
    end
  end
  page += 1

  # be nice to yahoo
  sleep (page_request_delay/1000.0) if morepages

  if items.empty?
    # in theory this shouldn't happen.
    puts "Oops, something has gone wrong - no inbox items were found."
    puts "Please check that you've followed all the instructions."
    puts "Possible causes:"
    puts "- You didn't include the correct authenticated cookie values"
    puts "- Your cookies have expired. Sign in again to Delicious and try again"
    puts "- You don't have network access right now"
    puts "- You have inbox data that this script wasn't designed to handle"
    puts "- Delicious is down or has changed something"
    puts "- Who knows?"
    exit
  end
end

# scraping done, write output in netscape bookmark style
outfile.puts '<!DOCTYPE NETSCAPE-Bookmark-file-1>'
outfile.puts '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">'
outfile.puts "<TITLE>Bookmarks</TITLE>"
outfile.puts "<H1>Bookmarks</H1>"
outfile.puts "<DL><p>"

items.each do |item|
  add_tags.split(/\s+/).each do |tag|
    # add custom tags
    item[:tags] << tag unless tag.empty?
  end
  if tag_sender
    # add sender tag
    item[:tags] << tag_sender_format.gsub(/\%USERNAME\%/,item[:from_user_name])
  end
  if description_sender
    # add sender to description
    desc = description_sender_format.dup
    desc.gsub!(/\%USERNAME\%/,item[:from_user_name])
    desc.gsub!(/\%PROFILENAME\%/,item[:from_user_profile_name])
    item[:description] << (" " + desc)
    item[:description].gsub!(/\A\s+/,'')
  end
  outfile.puts '<DT><A '+
    'HREF="' + CGI::escapeHTML(item[:url]) + '" ' +
    # forunately, Time.parse seems to work fine with the "16 DEC 10" style dates
    # that Delicious renders next to items. unforunately we don't get further
    # granularity than that:
    'ADD_DATE="' + Time.parse(item[:date]).to_i.to_s + '" '+
    # PRIVATE="0"/"1" is a convention started by Delicious' own export feature:
    'PRIVATE="' + (mark_private ? "1" : "0") + '" '+
    'TAGS="' + CGI::escapeHTML(item[:tags].join(",")) + '"' +
    '>' + CGI::escapeHTML(item[:title]) + "</A>"
  outfile.puts '<DD>' + CGI::escapeHTML(item[:description])
end

outfile.puts "</DL><p>"
outfile.close
puts "Exported #{items.length} total items to #{out_fn}"
