module Transactions::Vps
  class OsTemplate < ::Transaction
    t_name :vps_os_template
    t_type 2013
    queue :vps

    def params(vps, orig, os_template)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      {
          os_template: os_template.name,
          original: orig.name
      }
    end
  end
end
