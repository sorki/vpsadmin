module VpsAdmind
  class Commands::Vps::Hostname < Commands::Base
    handle 2004

    def exec
      Vps.new(@vps_id).set_params({:hostname => @hostname})
    end
  end
end
