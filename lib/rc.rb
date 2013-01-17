require 'lib/vpsadmind'
require 'lib/utils'

module VpsAdminCtl
	VERSION = "1.5.6"
	ACTIONS = [:status, :reload, :stop, :restart, :update]
	
	class RemoteControl
		def initialize(sock)
			@vpsadmind = VpsAdmind.new(sock)
		end
		
		def status
			if @opts[:workers]
				puts sprintf("%-5s %-20.15s %-5s %-18.16s %s", "VEID", "HANDLER", "TYPE", "TIME", "STEP") if @opts[:header]
				
				@res["workers"].sort.each do |w|
					puts sprintf("%-5d %-20.15s %-5d %-18.16s %s", w[0], w[1]["handler"], w[1]["type"], format_duration(Time.new.to_i - w[1]["start"]), w[1]["step"])
				end
			end
			
			if @opts[:consoles]
				puts sprintf("%-5s %s", "VEID", "LISTENERS")  if @opts[:header]
				
				@res["consoles"].sort.each do |c|
					puts sprintf("%-5d %d", c[0], c[1])
				end
			end
			
			unless @opts[:workers] || @opts[:consoles]
				puts "Version: #{@vpsadmind.version}"
				puts "Uptime: #{format_duration(Time.new.to_i - @res["start_time"])}"
				puts "Workers: #{@res["workers"].size}/#{@res["threads"]}"
				puts "Queue size: #{@res["queue_size"]}"
				puts "Exported consoles: #{@res["export_console"] ? @res["consoles"].size : "disabled"}"
			end
		end
		
		def reload
			puts "Config reloaded"
		end
		
		def stop
			puts "Stop scheduled"
		end
		
		def restart
			puts "Restart scheduled"
		end
		
		def update
			puts "Update scheduled"
		end
		
		def is_valid?(cmd)
			ACTIONS.include?(cmd.to_sym)
		end
		
		def exec(cmd, opts)
			return unless is_valid?(cmd)
			
			begin
				@vpsadmind.open
				@vpsadmind.cmd(cmd)
				@reply = @vpsadmind.reply
			rescue
				$stderr.puts "Error occured: #{$!}"
				$stderr.puts "Are you sure that vpsAdmind is running and configured properly?"
				return
			end
			
			unless @reply["status"] == "ok"
				return {:status => :failed, :error => @reply["error"]}
			end
			
			@res = @reply["response"]
			@opts = opts
			
			method(cmd).call()
		end
	end
end
