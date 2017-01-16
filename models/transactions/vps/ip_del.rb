module Transactions::Vps
  class IpDel < ::Transaction
    t_name :vps_ip_del
    t_type 2007
    queue :network

    def params(vps, ip, unregister = true)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      ret = {
          addr: ip.addr,
          version: ip.version,
          unregister: unregister,
          id: ip.id,
          user_id: ip.user_id || vps.m_id,
      }

      if unregister
        ret[:shaper] = {
            class_id: ip.class_id,
            max_tx: ip.max_tx,
            max_rx: ip.max_rx
        }
      end

      ret
    end
  end
end
