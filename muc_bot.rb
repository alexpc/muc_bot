#!/usr/bin/env ruby
# encoding: utf-8
require 'rubygems'
require 'singleton'
require 'xmpp4r'
require 'xmpp4r/muc/helper/simplemucclient'

if ARGV.size != 3
  puts "Usage: #{$0} <jid> <password> <room@conference/nick>"
  exit
end


# Print a line formatted depending on time.nil?
def print_line(time, line)
  if time.nil?
    puts line
  else
    puts "#{time.strftime('%I:%M')} #{line}"
  end
end


begin
#Jabber::debug = true
buffor = ''
cl = Jabber::Client.new(Jabber::JID.new(ARGV[0]))
cl.connect
cl.auth(ARGV[1])


# This is the SimpleMUCClient helper!
m = Jabber::MUC::SimpleMUCClient.new(cl)


# For waking up...
mainthread = Thread.current

# SimpleMUCClient callback-blocks
m.on_join { |time,nick|
  print_line time, "#{nick} has joined!"
  puts "Users: " + m.roster.keys.join(', ')
  buffor += "@@ #{nick} dołączył do pokoju!\n"
}
m.on_leave { |time,nick|
  print_line time, "#{nick} has left!"
  buffor += "@@ #{nick} wyszedł z pokoju!"
}
m.on_private_message{ |time,nick,text|
	print_line time, "<#{nick}> #{text}"
	#m.say(text,nick)
	if text.strip =~ /^rzu[cćt] (\d*)k(\d+)/i
		l_kosci = $1.to_i > 1 ? $1.to_i : 1
		w_kosci = $2.to_i > 1 ? $2.to_i : 6
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
			buffor += "[#{Time.new.strftime('%I:%M')}] #{text.gsub("\me",nick)}\n"
	    else
	  		buffor += "[#{Time.new.strftime('%I:%M')}] <#{nick}>: #{text}\n"
	    end
	end
  end

  if buffor.length > 100
	filename = Time.new.strftime('%Y-%m-%d_log.txt')
	aFile = File.new(filename, "a")
	aFile.write(buffor)
	aFile.close
	buffor = ''
  end	
}
m.on_room_message { |time,text|
  print_line time, "- #{text}"
}
m.on_subject { |time,nick,subject|
  print_line time, "*** (#{nick}) #{subject}"
}





m.join(ARGV[2])


=begin
eventrunner = Thread.start{|m|
	sleep(1) while mainthread.status!='sleep'
	begin
		m.say( "Aktywator!" + Time.new.strftime("%H:%I:%S"))
		sleep(rand(5))
	end while 1==1
}
eventrunner.run
=end


# Wait for being waken up by m.on_message
Thread.stop


cl.close

rescue Exception => e
	puts e.backtrace
end
