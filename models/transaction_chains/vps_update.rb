module TransactionChains
  class VpsUpdate < ::TransactionChain
    def link_chain(vps, attrs)
      lock(vps)

      attrs.each do |k, v|
        case k
          when 'vps_hostname'
            append(Transactions::Vps::Hostname, args: [vps, v]) do
              edit(vps, k => v)
            end

          when 'vps_template'
            # FIXME

          when 'dns_resolver_id'
            append(Transactions::Vps::DnsResolver, args: [vps, v]) do
              edit(vps, k => v.id)
            end
        end
      end
    end
  end
end
