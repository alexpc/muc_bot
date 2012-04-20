#!/usr/bin/env ruby
# encoding: utf-8
require 'rubygems'
require 'singleton'
require	'yaml'
require	'sqlite3'
require 'xmpp4r'
require 'xmpp4r/muc/helper/simplemucclient'
require 'net/http'
require 'xmlsimple'

unless File.exists? ('config.yml')
  puts "Cannot find config.yml file. Tried using sample_config.yml?"
  exit
end


# Print a line formatted depending on time.nil?
def print_line(time, line)
  if time.nil?
    puts line
  else
    puts "#{time.strftime('%H:%M')} #{line}"
  end
end

class Connector
    include Singleton
    def initialize
		config = YAML::load(File.open('config.yml'))
        @cl = Jabber::Client.new(Jabber::JID.new(config['jid']))
        @cl.connect
        @cl.auth(config['passwd'])
        @m = Jabber::MUC::SimpleMUCClient.new(@cl)
        @m.join(config['room']+'/'+config['nick'])
    end
	def close
		@cl.close
	end
    def muc
        return @m
    end
end

class Logger
    include Singleton
    def initialize
        @buffer = ''
    end
    def log(msg)
        @buffer += msg + "\n"
        if @buffer.length > 1
			self.save
        end
    end
	def save()
        filename = Time.new.strftime('logs/%Y-%m-%d_log.txt')
		aFile = File.new(filename, "a")
        aFile.write(@buffer)
        aFile.close
        @buffer = ''
		puts "Log saved in file #{filename}"
	end
end

class DbPool
	include Singleton
	def initialize
		@db = SQLite3::Database.new( "sql/db.sl3" )
	end
	def db
		return @db
	end
end
class User
	include Singleton
	def initialize
		@db = DbPool.instance.db
	end
	def login(nick)
		columns, *rows = @db.execute2( "select * from users where nick = ?",nick)
		if rows.empty?
			@db.execute("insert into users (nick,role,total_lines,total_letters,last_logged) values (?,?,?,?,?)",nick,'player',0,0,Time.new.to_i.to_s)
		else
			@db.execute("update users SET last_logged=? WHERE nick=?",Time.new.to_i.to_s,nick)
		end
		rescue Exception => e
			puts e.backtrace
		end

	end
	def log(nick,text)
		@db.execute("update users SET total_lines = total_lines+1,total_letters = total_letters + ? WHERE nick=?",text.length,nick)
	end
end

class Weather
	include Singleton
	def initialize
		@WeatherRSS = 'http://rss.wunderground.com/auto/rss_full/global/stations/12372.xml'
		@last_update = 0
		#@morning_range = 
		@day_range = (6..21)
	end
	def check
		update_after = (30 + rand(30) ) * 60
		return last_update + update_after <= Time.new
	end
	def update
		
	end
end
begin
#Jabber::debug = true

# This is the SimpleMUCClient helper!
m = Connector.instance.muc
logger = Logger.instance
#user = User.instance
#db = DbPool.instance.db
# For waking up...
mainthread = Thread.current

alivekeeper = Thread.new{
	sleep(1) while mainthread.status!='sleep'
	loop do
		m.get_room_configuration() 
		sleep(600)
		puts "Keeping alive (getting room config, saving buffer)"
		logger.save
	end
}
eventrunner = Thread.new{
	sleep(1) while mainthread.status!='sleep'
	loop do
		sleep(3600)
		puts "Event execution"
	end
}


# SimpleMUCClient callback-blocks
m.on_join { |time,nick|
	print_line time, "#{nick} has joined!"
	puts "Users: " + m.roster.keys.join(', ')
	logger.log("@@ #{nick} dołączył do pokoju!")
	User.instance.login(nick)
}
m.on_leave { |time,nick|
	print_line time, "#{nick} has left!"
	logger.log("@@ #{nick} wyszedł z pokoju!")
}
m.on_private_message{ |time,nick,text|
	print_line time, "<#{nick}> #{text}"
	if text.strip =~ /^rzu[cćt] (\d*)k(\d+)([+-]\d+)?/i
		l_kosci = $1.to_i > 1 ? $1.to_i : 1
		w_kosci = $2.to_i > 1 ? $2.to_i : 6
		b_kosci = $3.to_i
		sleep(0.5)
		wynik = 0;
		l_kosci.times { wynik += rand(w_kosci)+1 }
		wynik += b_kosci
		m.say("Rzut #{l_kosci}k#{w_kosci}#{$3}: #{wynik}",nick) 
	elsif text.strip =~ /^exit$/
		puts "exiting"
		m.exit
		mainthread.wakeup
	end
}
m.on_message { |time,nick,text|
	print_line time, "<#{nick}> #{text}"
	# Avoid reacting on messaged delivered as room history
	unless time
		# Bot: invite astro@spaceboyz.net
		if text.strip =~ /^(.+?): invite (.+)$/
			jid = $2
			if $1.downcase == m.jid.resource.downcase
				m.invite(jid => "Inviting you on behalf of #{nick}")
				m.say("Inviting #{jid}...")
			end
		# Bot: subject This is room is powered by XMPP4R
		elsif text.strip =~ /^(.+?): subject (.+)$/
			if $1.downcase == m.jid.resource.downcase
				m.subject = $2
				logger.log("** #{m.subject}")
			end
		# Bot: exit please
		elsif text.strip =~ /^(.+?): exit please$/
			if $1.downcase == m.jid.resource.downcase
				puts "exiting"
				m.exit "Exiting on behalf of #{nick}"
				mainthread.wakeup
			end
		else
			if text.include? '\me'
				logger.log("[#{Time.new.strftime('%H:%M')}] #{text.gsub("\me",nick)}")
		    else
				logger.log("[#{Time.new.strftime('%H:%M')}] <#{nick}> #{text}")
		    end
			User.instance.log(nick,text)
		end
	end
}
m.on_room_message { |time,text|
  print_line time, "- #{text}"
}
m.on_subject { |time,nick,subject|
  print_line time, "** (#{nick}) #{subject}"
  logger.log("** #{subject}")
}


# Wait for being waken up by m.on_message
Thread.stop

puts "Closing running threads"
eventrunner.exit
alivekeeper.exit

puts "Closing connection to server"
Connector.instance.close

puts "Forcing log save"
logger.save

rescue Exception => e
	puts $!
	puts e.backtrace
end
