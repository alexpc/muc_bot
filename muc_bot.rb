#!/usr/bin/env ruby
# encoding: utf-8
require 'rubygems'
require 'singleton'
require	'yaml'
require 'xmpp4r'
require 'xmpp4r/muc/helper/simplemucclient'

unless File.exists? ('config.yml')
  puts "Usage: #{$0} <jid> <password> <room@conference/nick>"
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
            filename = Time.new.strftime('logs/%Y-%m-%d_log.txt')
            aFile = File.new(filename, "a")
            aFile.write(@buffer)
            aFile.close
            @buffer = ''
        end
    end
end


begin
#Jabber::debug = true

# This is the SimpleMUCClient helper!
m = Connector.instance.muc
logger = Logger.instance
# For waking up...
mainthread = Thread.current

eventrunner = Thread.new{
	sleep(0.1) while mainthread.status!='sleep'
	begin
		m.say( "Mamy godzinę " + Time.new.strftime("%H:%M:%S"))
		sleep(60)
	end while 1==1
}



# SimpleMUCClient callback-blocks
m.on_join { |time,nick|
	print_line time, "#{nick} has joined!"
	puts "Users: " + m.roster.keys.join(', ')
	logger.log("@@ #{nick} dołączył do pokoju!")
}
m.on_leave { |time,nick|
	print_line time, "#{nick} has left!"
	logger.log("@@ #{nick} wyszedł z pokoju!")
}
m.on_private_message{ |time,nick,text|
	print_line time, "<#{nick}> #{text}"
	if text.strip =~ /^rzu[cćt] (\d*)k(\d+)/i
		l_kosci = $1.to_i > 1 ? $1.to_i : 1
		w_kosci = $2.to_i > 1 ? $2.to_i : 6
		sleep(0.5)
		m.say("Rzut #{l_kosci}k#{w_kosci}: #{l_kosci*(rand(w_kosci)+1)}",nick) 
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
				logger.log("[#{Time.new.strftime('%I:%M')}] #{text.gsub("\me",nick)}")
		    else
				logger.log("[#{Time.new.strftime('%I:%M')}] <#{nick}>: #{text}")
		    end
		end
	end
}
m.on_room_message { |time,text|
  print_line time, "- #{text}"
}
m.on_subject { |time,nick,subject|
  print_line time, "*** (#{nick}) #{subject}"
}





# Wait for being waken up by m.on_message
Thread.stop



cl.close

rescue Exception => e
	puts e.backtrace
end
